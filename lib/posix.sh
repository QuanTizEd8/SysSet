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
  local _pbifs_prefix _pbifs_version _pbifs_url _pbifs_tmpdir _pbifs_bin
  _pbifs_prefix="${1:?posix__install_bash_from_source: prefix required}"
  _pbifs_version="${2:?posix__install_bash_from_source: version required}"
  _pbifs_url="https://ftp.gnu.org/gnu/bash/bash-${_pbifs_version}.tar.gz"

  [ "$(uname -s)" = "Darwin" ] && posix__bootstrap_xcode

  _pbifs_tmpdir="$(mktemp -d /tmp/bash-src.XXXXXX)"

  logging__download "Downloading bash ${_pbifs_version} source..."
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL --compressed \
      --retry 5 --retry-delay 5 --retry-connrefused \
      -H "User-Agent: devfeats" \
      "${_pbifs_url}" | tar xz -C "${_pbifs_tmpdir}"
  elif command -v wget > /dev/null 2>&1; then
    wget -qO- "${_pbifs_url}" | tar xz -C "${_pbifs_tmpdir}"
  else
    rm -rf "${_pbifs_tmpdir}"
    logging__error "Neither curl nor wget found; cannot download bash source."
    return 1
  fi || {
    rm -rf "${_pbifs_tmpdir}"
    logging__error "Failed to download or extract bash ${_pbifs_version} source."
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
