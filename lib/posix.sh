# shellcheck shell=bash
# POSIX-compatible helper functions shared between install.sh (POSIX bootstrap
# phase) and install.bash (bash runtime phase via lib/__init__.bash).
#
# All functions in this file MUST be compatible with POSIX sh: no [[ ]],
# no bash arrays, no process substitution. Return 1 on failure; never exit.

posix__bootstrap_xcode() {
  # @brief posix__bootstrap_xcode — Ensure Xcode Command Line Tools are installed (macOS only).
  #
  # Headlessly installs the Xcode Command Line Tools via `softwareupdate` when
  # they are absent. This provides `make`, `cc`, and other build essentials
  # required for compiling software from source on macOS.
  #
  # No-op on non-macOS systems. Requires `sudo` privileges to install.
  #
  # Returns: 0 when CLTs are present (or successfully installed), 1 on failure.
  [ "$(uname -s)" = "Darwin" ] || return 0
  if xcode-select -p > /dev/null 2>&1; then
    logging__success "Xcode Command Line Tools already installed at '$(xcode-select -p 2> /dev/null)'."
    return 0
  fi
  logging__inspect "Xcode Command Line Tools not found — installing headlessly."
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  local _xcode_pkg
  _xcode_pkg="$(softwareupdate -l 2>&1 |
    grep -E '\*.*Command Line Tools' |
    tail -1 |
    sed 's/.*\* //')" || true
  if [ -z "$_xcode_pkg" ]; then
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    logging__error "No 'Command Line Tools' package found in softwareupdate -l."
    logging__info "Install manually with: xcode-select --install"
    return 1
  fi
  logging__install "Installing via softwareupdate: '${_xcode_pkg}'"
  if ! softwareupdate -i "$_xcode_pkg" --verbose; then
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    logging__error "softwareupdate failed to install '${_xcode_pkg}'."
    logging__info "Install manually with: xcode-select --install"
    return 1
  fi
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  logging__success "Xcode Command Line Tools installed."
  return 0
}

posix__quote() {
  # @brief posix__quote <value> — Print <value> as a POSIX sh single-quoted string literal.
  #
  # Safe for arbitrary content, including embedded newlines and single quotes.
  # Useful for writing dynamically-generated POSIX sh scripts (e.g. lifecycle
  # hook scripts with runtime-computed option values).
  #
  # Pure POSIX parameter expansion (no external tools, no bash-only `${var//}`)
  # so this works identically under dash/ash and bash.
  #
  # Args:
  #   <value>  String to quote.
  #
  # Stdout: the quoted literal (no trailing newline).
  local _pq_in="$1"
  local _pq_out=''
  local _pq_chunk
  while [ -n "$_pq_in" ]; do
    case $_pq_in in
      "'"*)
        _pq_out="${_pq_out}'\\''"
        _pq_in=${_pq_in#?}
        ;;
      *)
        _pq_chunk=${_pq_in%%\'*}
        _pq_out="${_pq_out}${_pq_chunk}"
        _pq_in=${_pq_in#"$_pq_chunk"}
        ;;
    esac
  done
  printf "'%s'" "$_pq_out"
}

_posix__fetch_retryable() {
  # _posix__fetch_retryable <exit-code> <status> <tool> <stderr-file> — Retry bootstrap download failures unless they are certainly persistent.
  #
  # Bootstrap downloads are idempotent. This mirrors lib/net.bash without
  # Bash-only helpers: unknown statuses and client failures are retried rather
  # than risking a failure during a temporary CDN, proxy, or registry incident.
  local _rc="$1" _status="$2" _tool="$3" _stderr_file="$4"
  case "$_status" in
    400 | 401 | 405 | 406 | 407 | 410 | 411 | 413 | 414 | 415 | 416 | 422 | 426 | 428 | 431 | 451) return 1 ;;
  esac
  if [ "$_tool" = curl ]; then
    case "$_rc" in
      1 | 2 | 3 | 4 | 23 | 26 | 27 | 37 | 42 | 43 | 45 | 47 | 48 | 49 | 53 | 54 | 58 | 59 | 60 | 63 | 65 | 66 | 67 | 89 | 90 | 91 | 93 | 94 | 98 | 99 | 100 | 101) return 1 ;;
      35)
        grep -Eiq 'certificate problem|certificate verify failed|unable to get local issuer|self[ -]signed certificate|no alternative certificate subject name matches|peer certificate' "$_stderr_file" && return 1
        ;;
    esac
  else
    case "$_rc" in
      # GNU wget command-line parse, local file I/O, certificate, or auth errors.
      2 | 3 | 5 | 6) return 1 ;;
    esac
  fi
  return 0
}

_posix__pm_output_has_failure() {
  # _posix__pm_output_has_failure <transcript> — Detect a transport/repository error reported with exit 0.
  # Match TLS/SSL and certificate diagnostics as words and diagnostic phrases,
  # rather than arbitrary substrings in successful package lists such as
  # libcurl*-gnutls and liberror-perl.
  grep -Eiq 'could not resolve|couldn.t resolve|temporary failure|failed to fetch|failed retrieving file|failed to download metadata|download \(curl\) error|curl error|connection (timed out|reset|refused|closed|aborted)|network is unreachable|no route to host|unexpected eof|(^|[^[:alnum:]])(gnutls|tls|ssl)[^[:alnum:]]+(connection|handshake|certificate|alert|recv|receive|error|failed)|(^|[^[:alnum:]])certificate[^[:alnum:]]+(verification|verify|validation|problem|error|failed)|http[^[:alnum:]]*(408|425|429|5[0-9][0-9])|hash sum mismatch|checksum mismatch|some index files failed to download|usable url not found|repository.*(unavailable|unreachable)|repomd\.xml.*(failed|unavailable)' "$1"
}

_posix__pm_certainly_local_failure() {
  # _posix__pm_certainly_local_failure <transcript> — Identify only retry-proof local failures.
  grep -Eiq 'Malformed line [0-9]+ in source list|The list of sources could not be read|Type .+ is not known on line|Error in configuration file|^([Ee]rror: )?(unknown|invalid) (command|option|argument)' "$1"
}

posix__run_with_retry() {
  # @brief posix__run_with_retry <pm> <operation> <command>... — Run a bootstrap PM operation with retry-by-default semantics.
  #
  # Both output streams are captured because APT and DNF can return success
  # after emitting repository-fetch errors. All nonzero outcomes retry unless
  # their diagnostic proves a local configuration or invocation error.
  local _pm="$1" _operation="$2"
  shift 2
  local _max="${DEVFEATS_OSPKG_RETRIES:-5}" _delay="${DEVFEATS_OSPKG_RETRY_DELAY:-10}"
  local _tmpdir _stdout _stderr _transcript _attempt _rc
  case "$_operation" in update | install | repo) ;; *)
    logging__error "invalid bootstrap package-manager operation."
    return 1
    ;;
  esac
  [ "$#" -gt 0 ] || {
    logging__error "bootstrap package-manager command is required."
    return 1
  }
  if ! printf '%s\n' "$_max" | grep -Eq '^[0-9]+$' ||
    ! printf '%s\n' "$_delay" | grep -Eq '^[0-9]+$'; then
    logging__error "invalid bootstrap package-manager retry configuration."
    return 1
  fi
  [ "$_max" -gt 0 ] || _max=1
  _tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devfeats-posix-pm.XXXXXX")" || return 1
  _stdout="${_tmpdir}/stdout"
  _stderr="${_tmpdir}/stderr"
  _transcript="${_tmpdir}/transcript"
  _attempt=1
  while [ "$_attempt" -le "$_max" ]; do
    : > "$_stdout"
    : > "$_stderr"
    _rc=0
    "$@" < /dev/null > "$_stdout" 2> "$_stderr" || _rc=$?
    cat "$_stdout"
    cat "$_stderr" >&2
    cat "$_stdout" "$_stderr" > "$_transcript"
    if [ "$_rc" -eq 0 ] && ! _posix__pm_output_has_failure "$_transcript"; then
      rm -rf "$_tmpdir"
      return 0
    fi
    if [ "$_rc" -eq 0 ]; then
      _rc=1
      logging__warn "Bootstrap package manager reported a repository/transport failure despite exit 0."
    fi
    if _posix__pm_certainly_local_failure "$_transcript"; then
      logging__error "Bootstrap package-manager operation failed due to a local configuration or invocation error — not retrying."
      rm -rf "$_tmpdir"
      return "$_rc"
    fi
    if [ "$_attempt" -lt "$_max" ]; then
      logging__warn "Bootstrap ${_pm} ${_operation} attempt ${_attempt}/${_max} failed (exit ${_rc}); retrying in ${_delay}s."
      sleep "$_delay"
    fi
    _attempt=$((_attempt + 1))
  done
  rm -rf "$_tmpdir"
  return "$_rc"
}

_posix__fetch_url_file() {
  # _posix__fetch_url_file <url> <dest> — Fetch one URL atomically with retry-by-default classification during POSIX bootstrap.
  local _url="$1" _dest="$2"
  local _max="${DEVFEATS_NET_FETCH_RETRIES:-5}" _delay="${DEVFEATS_NET_FETCH_DELAY:-5}"
  local _tmpdir _part _headers _stderr _tool _attempt _rc _status _status_output
  if ! printf '%s\n' "$_max" | grep -Eq '^[0-9]+$' || ! printf '%s\n' "$_delay" | grep -Eq '^[0-9]+$'; then
    logging__error "invalid bootstrap download retry configuration."
    return 1
  fi
  [ "$_max" -gt 0 ] || _max=1
  _tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devfeats-posix-fetch.XXXXXX")" || return 1
  _part="${_tmpdir}/payload"
  _headers="${_tmpdir}/headers"
  _stderr="${_tmpdir}/stderr"
  _tool=""
  if command -v curl > /dev/null 2>&1; then
    _tool=curl
  elif command -v wget > /dev/null 2>&1; then
    _tool=wget
  else
    rm -rf "$_tmpdir"
    logging__error "Neither curl nor wget found; cannot download '${_url}'."
    return 1
  fi

  _attempt=1
  while [ "$_attempt" -le "$_max" ]; do
    : > "$_part"
    : > "$_headers"
    : > "$_stderr"
    _rc=0
    _status=000
    if [ "$_tool" = curl ]; then
      _status_output="$(curl -fsSL --compressed -D "$_headers" -w '%{http_code}' -o "$_part" \
        -H 'User-Agent: devfeats' "$_url" 2> "$_stderr")" || _rc=$?
      case "$_status_output" in
        *[0-9][0-9][0-9]) _status="${_status_output##*[!0-9]}" ;;
      esac
    else
      wget -q -S -O "$_part" --header='User-Agent: devfeats' "$_url" 2> "$_stderr" || _rc=$?
      _status="$(awk '$1 ~ /^HTTP\/[0-9.]+$/ && $2 ~ /^[0-9][0-9][0-9]$/ { status = $2 } END { print status + 0 }' "$_stderr" 2> /dev/null)"
      [ "$_status" -ge 100 ] 2> /dev/null || _status=000
    fi
    case "$_status" in
      000 | 2[0-9][0-9])
        if [ "$_rc" -eq 0 ] && mv -f "$_part" "$_dest"; then
          rm -rf "$_tmpdir"
          return 0
        fi
        ;;
    esac
    [ "$_rc" -eq 0 ] && _rc=22
    if _posix__fetch_retryable "$_rc" "$_status" "$_tool" "$_stderr" && [ "$_attempt" -lt "$_max" ]; then
      logging__warn "Bootstrap download attempt ${_attempt}/${_max} for '${_url}' failed; retrying in ${_delay}s."
      sleep "$_delay"
      _attempt=$((_attempt + 1))
      continue
    fi
    cat "$_stderr" >&2
    rm -rf "$_tmpdir"
    logging__error "Failed to download '${_url}' with ${_tool} (exit ${_rc}, status ${_status})."
    return "$_rc"
  done
  rm -rf "$_tmpdir"
  return 1
}

posix__install_bash_from_source() {
  # @brief posix__install_bash_from_source <prefix> <version> — Download, compile, and install bash from GNU FTP.
  #
  # Compiles bash from the official GNU FTP source tarball and installs the
  # binary to `<prefix>/bin/bash`. Only the binary is installed (no `make install`);
  # this is intentional for lightweight bootstrap use. The feature install pipeline
  # runs `make install` via the autotools template for a complete installation.
  #
  # Calls posix__bootstrap_xcode on macOS to ensure build tools are available.
  # Prints the installed binary path on stdout. Returns 1 on any failure.
  local _pbifs_prefix _pbifs_version _pbifs_url _pbifs_tmpdir _pbifs_bin _pbifs_archive
  _pbifs_prefix="${1:?posix__install_bash_from_source: prefix required}"
  _pbifs_version="${2:?posix__install_bash_from_source: version required}"
  _pbifs_url="https://ftp.gnu.org/gnu/bash/bash-${_pbifs_version}.tar.gz"

  [ "$(uname -s)" = "Darwin" ] && posix__bootstrap_xcode

  _pbifs_tmpdir="$(mktemp -d /tmp/bash-src.XXXXXX)"
  _pbifs_archive="${_pbifs_tmpdir}/bash-${_pbifs_version}.tar.gz"

  logging__download "Downloading bash ${_pbifs_version} source..."
  _posix__fetch_url_file "${_pbifs_url}" "${_pbifs_archive}" || {
    rm -rf "${_pbifs_tmpdir}"
    logging__error "Failed to download bash ${_pbifs_version} source."
    return 1
  }
  tar xzf "${_pbifs_archive}" -C "${_pbifs_tmpdir}" || {
    rm -rf "${_pbifs_tmpdir}"
    logging__error "Failed to extract bash ${_pbifs_version} source."
    return 1
  }

  logging__build "Compiling bash ${_pbifs_version} (this may take a minute)..."
  (
    cd "${_pbifs_tmpdir}/bash-${_pbifs_version}" &&
      ./configure --prefix="${_pbifs_prefix}" --without-bash-malloc --without-readline \
        > /dev/null 2>&1 &&
      make > /dev/null 2>&1
  ) || {
    rm -rf "${_pbifs_tmpdir}"
    logging__error "bash ${_pbifs_version} build failed."
    return 1
  }

  _pbifs_bin="${_pbifs_tmpdir}/bash-${_pbifs_version}/bash"
  if [ ! -x "${_pbifs_bin}" ]; then
    rm -rf "${_pbifs_tmpdir}"
    logging__error "Compiled bash binary not found after make."
    return 1
  fi

  mkdir -p "${_pbifs_prefix}/bin"
  cp "${_pbifs_bin}" "${_pbifs_prefix}/bin/bash"
  chmod a+x "${_pbifs_prefix}/bin/bash"
  rm -rf "${_pbifs_tmpdir}"

  logging__success "bash ${_pbifs_version} compiled and installed to '${_pbifs_prefix}/bin/bash'."
  printf '%s\n' "${_pbifs_prefix}/bin/bash"
}
