# shellcheck shell=bash
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# Bootstrap installer functions for tools that lib modules depend on at runtime.
# These call install__release_asset directly to avoid circular dependencies:
# if the feature scripts were used instead, their base-dependency install would
# call back into the same lib (e.g. ospkg → yq → ospkg).

_BOOTSTRAP__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# In-process cache for the yq binary path; set by bootstrap__yq on first call.
_BOOTSTRAP__YQ_BIN=
# In-process cache for the jsonschema binary path; set by bootstrap__jsonschema on first call.
_BOOTSTRAP__JSONSCHEMA_BIN=

_bootstrap__tool() {
  # _bootstrap__tool [options] — Check → install → recheck loop for a single CLI tool.
  #
  # Options:
  #   --cmd <cmd>       Command to check (repeatable; any found → success).
  #   --pkg <pkg>       Package name for ospkg__install_tracked <group> <pkg>.
  #   --manifest <path> Manifest file path for ospkg__run --manifest <path> --build-group <group>.
  #   --group <id>      Build group for package tracking.
  #   --skip-darwin     Skip the install step on Darwin; go straight to the failure path.
  #   --warn            Use logging__warn on failure instead of logging__error.
  #   --info            Use logging__info on failure instead of logging__error.
  #   --msg <str>       Full failure message (overrides the default construction).
  local -a _cmds=()
  local _pkg="" _manifest="" _group="" _skip_darwin=false _level="error" _msg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cmd)
        _cmds+=("$2")
        shift 2
        ;;
      --pkg)
        _pkg="$2"
        shift 2
        ;;
      --manifest)
        _manifest="$2"
        shift 2
        ;;
      --group)
        _group="$2"
        shift 2
        ;;
      --skip-darwin)
        _skip_darwin=true
        shift
        ;;
      --warn)
        _level="warn"
        shift
        ;;
      --info)
        _level="info"
        shift
        ;;
      --msg)
        _msg="$2"
        shift 2
        ;;
      *)
        logging__error "_bootstrap__tool: unknown option '$1'"
        return 1
        ;;
    esac
  done
  local _c
  for _c in "${_cmds[@]}"; do
    command -v "$_c" > /dev/null 2>&1 && return 0
  done
  if [[ "$_skip_darwin" == true && "$(os__kernel)" == "Darwin" ]]; then
    # Tool is not applicable on macOS; skip gracefully.
    [[ -n "$_msg" ]] && "logging__${_level}" "$_msg"
    return 0
  fi
  if [[ -n "$_manifest" ]]; then
    ospkg__run --manifest "$_manifest" --build-group "$_group" || true
  elif [[ -n "$_pkg" ]]; then
    ospkg__install_tracked "$_group" "$_pkg"
  fi
  for _c in "${_cmds[@]}"; do
    command -v "$_c" > /dev/null 2>&1 && return 0
  done
  local _default_msg="'${_cmds[0]:-tool}' could not be installed."
  "logging__${_level}" "${_msg:-${_default_msg}}"
  return 1
}

bootstrap__jq() {
  # @brief bootstrap__jq — Ensure jq is on PATH, downloading the upstream release
  # binary from GitHub if absent.
  #
  # Deliberately does not use ospkg (the OS package manager) the way most
  # other bootstrap__* functions do: that requires root or passwordless sudo,
  # which defeats non-privileged installs entirely. It also cannot resolve
  # the version via github__resolve_version like most other tools do — that
  # function calls bootstrap__jq internally (via json__query) to parse the
  # GitHub API response, which would make bootstrapping jq depend on jq
  # already being installed. github__latest_tag breaks that cycle: it falls
  # back to grep/sed parsing when jq is not yet available. Otherwise mirrors
  # bootstrap__yq's direct-binary-download approach; jq publishes a
  # sha256sum.txt release asset, so install__release_asset's sidecar
  # auto-probe verifies the download without any extra checksum handling.
  #
  # Returns: 0 on success, 1 if jq cannot be installed.
  #
  # Reentrancy guard: github__latest_tag (called below to resolve jq's own
  # version) parses the GitHub API response via _json__root_scalar_stdin,
  # which itself calls bootstrap__jq to ensure jq is available — a recursive
  # re-entry while this very call is still bootstrapping it. Without this
  # guard, that inner call restarts the whole bootstrap (a fresh API fetch,
  # a fresh parse attempt, a fresh recursive call, ...) instead of failing
  # fast, looping forever whenever the API call keeps succeeding. Failing
  # fast here makes the inner probe fail gracefully instead, so
  # github__latest_tag falls through to its documented grep/sed fallback.
  [[ "${_BOOTSTRAP__JQ_IN_PROGRESS:-false}" == true ]] && return 1
  command -v jq > /dev/null 2>&1 && return 0

  # Fast path: previously bootstrapped binary still alive.
  local _state_ctx _state_path _state_group
  install__read_state "jq" _state_ctx _state_path _state_group
  if [[ -x "${_state_path:-}" ]]; then
    logging__skip "Reusing bootstrapped jq at '${_state_path}'."
    local _state_dir
    _state_dir="$(dirname "${_state_path}")"
    export PATH="${_state_dir}:${PATH}"
    return 0
  fi

  _BOOTSTRAP__JQ_IN_PROGRESS=true
  _bootstrap__jq_impl
  local _bootstrap_jq_rc=$?
  _BOOTSTRAP__JQ_IN_PROGRESS=false
  return "$_bootstrap_jq_rc"
}

_bootstrap__jq_impl() {
  # _bootstrap__jq_impl  (internal)
  #
  # The actual download/install logic for bootstrap__jq, split out so the
  # reentrancy guard in bootstrap__jq can reset its flag around a single call
  # regardless of which of this function's several early-return paths fires.
  logging__install "Bootstrapping jq from the upstream GitHub release."

  local _tag
  _tag="$(github__latest_tag "jqlang/jq")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to resolve the latest jq release tag."
    return "$_rc"
  }

  local _os _arch
  _os="$(os__release_kernel macos)"
  _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to detect OS kernel."
    return "$_rc"
  }
  _arch="$(os__release_arch)"
  _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to detect CPU architecture."
    return "$_rc"
  }
  case "${_arch}" in
    amd64 | arm64) ;;
    *)
      logging__error "unsupported architecture '${_arch}' for jq bootstrap."
      return 1
      ;;
  esac

  local _asset="jq-${_os}-${_arch}"
  local _base="https://github.com/jqlang/jq/releases/download/${_tag}"
  local _install_dir
  _install_dir="$(file__tmpdir "bootstrap/jq")"
  logging__install "Installing jq binary '${_asset}' from '${_base}'."
  # install__release_asset (via uri__fetch_asset) prints the installed path to
  # stdout — harmless for bootstrap__yq's callers, which capture it via
  # $(bootstrap__yq), but bootstrap__jq's callers don't capture its stdout at
  # all, and this function is itself called deep inside other $(...)
  # captures (e.g. github__resolve_version resolving a *different* tool's
  # version) — left unsuppressed, that path silently corrupts whichever
  # outer capture happens to be active. Discard it here.
  install__release_asset \
    --asset-uri "${_base}/${_asset}" \
    --binary-dest "${_install_dir}/jq" > /dev/null
  _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to install jq binary '${_asset}' from '${_base}'."
    return "$_rc"
  }

  install__state_record "jq" "internal" "binary" "${_install_dir}/jq" "devfeats-bootstrap-jq" || true
  export PATH="${_install_dir}:${PATH}"
  command -v jq > /dev/null 2>&1
}

bootstrap__flock() {
  # @brief bootstrap__flock — Ensure flock is available; install util-linux via ospkg if absent.
  # Returns: 0 when flock is on PATH; 1 otherwise. Non-fatal: callers fall back to spin-lock.
  _bootstrap__tool --cmd flock \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/flock.yaml" --group "lib-lock" \
    --skip-darwin --info --msg "'flock' not available; using spin-lock fallback."
}

bootstrap__curl() {
  # @brief bootstrap__curl — Ensure curl is on PATH, installing via ospkg if absent.
  # Returns: 0 on success, 1 if curl cannot be installed.
  _bootstrap__tool --cmd curl --pkg curl --group "lib-net"
}

bootstrap__ca_certs() {
  # @brief bootstrap__ca_certs — Ensure a CA certificate bundle is present; install ca-certificates via ospkg if missing.
  #
  # macOS uses the system keychain natively (curl and wget pick it up without a
  # .crt bundle), so the check is skipped there. On Linux, an absent or empty
  # bundle causes TLS errors for all HTTPS fetches. Checks known bundle locations
  # across distributions (Debian/Ubuntu/Alpine, openSUSE, Fedora/RHEL/CentOS).
  #
  # Returns: 0 on success, 1 if no CA bundle is present after install.

  # macOS uses its own keychain; curl/wget use it natively without a .crt file.
  [ "$(uname -s)" = "Darwin" ] && return 0
  # Known CA bundle locations across distributions:
  #   Debian/Ubuntu/Alpine: /etc/ssl/certs/ca-certificates.crt
  #   openSUSE:             /etc/ssl/ca-bundle.pem
  #   Fedora/RHEL/CentOS:   /etc/pki/tls/certs/ca-bundle.crt
  local _b
  for _b in \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/ssl/ca-bundle.pem \
    /etc/pki/tls/certs/ca-bundle.crt; do
    [ -s "$_b" ] && return 0
  done
  logging__info "CA certificate bundle missing — installing ca-certificates."
  ospkg__install_tracked "lib-net" ca-certificates
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to install ca-certificates."
    return "$_rc"
  }
  for _b in \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/ssl/ca-bundle.pem \
    /etc/pki/tls/certs/ca-bundle.crt; do
    [ -s "$_b" ] && return 0
  done
  logging__error "ca-certificates could not be installed."
  return 1
}

bootstrap__strings() {
  # @brief bootstrap__strings — Ensure strings (binutils) is available, installing via ospkg if absent.
  # Returns: 0 when strings is on PATH (before or after install), 1 otherwise (non-fatal).
  _bootstrap__tool --cmd strings \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/binutils.yaml" --group "lib-shell" \
    --warn --msg "'strings' not available; falling back to os-release detection."
}

bootstrap__sha256sum() {
  # @brief bootstrap__sha256sum — Ensure sha256sum or shasum is available; installs coreutils on Linux if absent.
  # Returns: 0 when a sha256 tool is available; 1 otherwise (non-fatal: caller falls back to cksum).
  _bootstrap__tool --cmd sha256sum --cmd shasum \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/coreutils-linux.yaml" --group "lib-uri" \
    --warn --msg "neither 'sha256sum' nor 'shasum' available; falling back to cksum for URI hashing."
}

bootstrap__coreutils() {
  # @brief bootstrap__coreutils — Ensure coreutils (id, stat, whoami) are available; install via ospkg if absent.
  # Returns: 0 on success, 1 if coreutils cannot be installed.
  _bootstrap__tool --cmd id \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/coreutils-linux.yaml" --group "lib-users" \
    --msg "'id' is required but could not be installed."
}

bootstrap__find() {
  # @brief bootstrap__find — Ensure find is on PATH, installing findutils via ospkg if absent.
  # Returns: 0 on success, 1 if find cannot be installed.
  _bootstrap__tool --cmd find --pkg findutils --group "lib-find" \
    --msg "'find' is required but could not be installed."
}

bootstrap__getent() {
  # @brief bootstrap__getent — Ensure getent is available; install the platform libc package via ospkg if absent.
  # Returns: 0 when getent is on PATH; 1 otherwise. Non-fatal: macOS does not have getent; callers fall back to dscl.
  _bootstrap__tool --cmd getent \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/getent.yaml" --group "lib-users" \
    --skip-darwin --info --msg "'getent' not available; falling back to dscl or /etc/passwd for home resolution."
}

bootstrap__sudo() {
  # @brief bootstrap__sudo — Ensure sudo (visudo) is available; install via ospkg if absent.
  # Returns: 0 on success, 1 if sudo cannot be installed.
  _bootstrap__tool --cmd visudo \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/sudo.yaml" --group "lib-users" \
    --msg "'sudo' (visudo) is required but could not be installed."
}

bootstrap__shadow_utils() {
  # @brief bootstrap__shadow_utils — Ensure useradd, groupadd, and usermod are available; install shadow-utils via ospkg if absent.
  # Returns: 0 on success, 1 if shadow-utils cannot be installed (non-fatal: logged as warning).
  # On macOS: shadow-utils is Linux only; skipped (macOS uses dscl for user management).
  _bootstrap__tool --cmd groupadd \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/shadow-utils.yaml" --group "lib-users" \
    --skip-darwin --warn --msg "shadow-utils (useradd, groupadd, usermod) is required but could not be installed."
}

bootstrap__su() {
  # @brief bootstrap__su — Ensure su is on PATH, installing via ospkg if absent.
  # Returns: 0 on success, 1 if su cannot be installed.
  _bootstrap__tool --cmd su \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/chsh.yaml" --group "lib-users" \
    --skip-darwin \
    --msg "'su' is required but could not be installed."
}

bootstrap__gpg() {
  # @brief bootstrap__gpg [<group_id>] — Ensure gpg is available, auto-installing gnupg if needed.
  #
  # Args:
  #   [group_id]  Tracking group for the auto-installed package (default: lib-verify).
  #
  # Returns: 0 if gpg is available, 1 if installation fails.
  local _group="${1:-lib-verify}"
  _bootstrap__tool --cmd gpg \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/gnupg.yaml" \
    --group "$_group" \
    --msg "gpg still not found after installing gnupg."
}

bootstrap__install_cmd() {
  # @brief bootstrap__install_cmd — Ensure the install command (coreutils) is available.
  # install is provided by GNU coreutils on Linux and BSD utils on macOS. Falls back to ospkg when missing.
  # Returns: 0 on success, 1 if install is unavailable.
  _bootstrap__tool --cmd install \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/coreutils-linux.yaml" --group "lib-file" \
    --msg "'install' is required but could not be installed."
}

bootstrap__npm() {
  # @brief bootstrap__npm — Ensure the npm CLI is on PATH, installing nodejs if needed.
  # Returns: 0 if npm is available (or was just installed), 1 otherwise.
  command -v npm > /dev/null 2>&1 && return 0
  logging__install "npm not found on PATH — installing nodejs/npm via OS package manager."
  local _rc=0
  set +e
  ospkg__install_user nodejs npm
  _rc=$?
  if ((_rc != 0)); then
    logging__install "Retrying nodejs-only install after nodejs+npm attempt failed."
    ospkg__install_user nodejs
    _rc=$?
  fi
  set -e
  if ((_rc != 0)); then
    logging__error "failed to install nodejs/npm."
    return 1
  fi
  command -v npm > /dev/null 2>&1 || {
    logging__error "npm still not available after install attempt."
    return 1
  }
}

bootstrap__unzip() {
  # @brief bootstrap__unzip — Ensure unzip is on PATH, installing via ospkg if absent.
  # Returns: 0 on success, 1 if unzip cannot be installed.
  _bootstrap__tool --cmd unzip --pkg unzip --group "lib-bootstrap" \
    --msg "unzip is required to extract .zip archives but could not be installed."
}

bootstrap__xz() {
  # @brief bootstrap__xz — Ensure xz is on PATH, installing xz-utils via ospkg if absent.
  # Returns: 0 on success, 1 if xz cannot be installed.
  _bootstrap__tool --cmd xz \
    --manifest "${_BOOTSTRAP__LIB_DIR}/deps/xz.yaml" --group "lib-bootstrap" \
    --msg "xz is required to extract .tar.xz archives but could not be installed."
}

bootstrap__bzip2() {
  # @brief bootstrap__bzip2 — Ensure bzip2 is on PATH, installing via ospkg if absent.
  # Returns: 0 on success, 1 if bzip2 cannot be installed.
  _bootstrap__tool --cmd bzip2 --pkg bzip2 --group "lib-bootstrap" \
    --msg "bzip2 is required to extract .tar.bz2 archives but could not be installed."
}

bootstrap__gzip() {
  # @brief bootstrap__gzip — Ensure gzip is on PATH, installing via ospkg if absent.
  # Returns: 0 on success, 1 if gzip cannot be installed.
  _bootstrap__tool --cmd gzip --pkg gzip --group "lib-bootstrap" \
    --msg "gzip is required to extract .tar.gz archives but could not be installed."
}

bootstrap__tar() {
  # @brief bootstrap__tar — Ensure tar is on PATH, installing via ospkg if absent.
  # Returns: 0 on success, 1 if tar cannot be installed.
  _bootstrap__tool --cmd tar --pkg tar --group "lib-bootstrap" \
    --msg "tar is required to extract .tar archives but could not be installed."
}

_bootstrap__yq_compatible() {
  # @brief _bootstrap__yq_compatible <bin> — Return 0 when <bin> is mikefarah/yq (supports -o=json).
  local _bin="${1-}"
  [[ -n "$_bin" ]] || {
    logging__error "yq binary path is empty."
    return 1
  }
  "$_bin" -o=json '.' /dev/null > /dev/null 2>&1
}

bootstrap__yq() {
  # @brief bootstrap__yq [<version-spec>] — Ensure mikefarah/yq is available and print its path.
  #
  # Returns the path of an already-installed compatible yq when one exists (fast
  # path).  Otherwise downloads the release binary, verifies via yq's custom
  # checksum script, and caches the result. Sets _BOOTSTRAP__YQ_BIN for callers
  # that need the path without a subshell.
  #
  # Args:
  #   [version-spec]  Version spec accepted by github__resolve_version (e.g.
  #                   "stable", "latest", "4.44.3"). Defaults to "stable".
  #
  # Stdout: absolute path to a mikefarah/yq-compatible binary.
  # Returns: 0 on success, 1 on any failure.
  local _spec="${1:-stable}"

  # Fast path 1: in-process cache.
  if [[ -n "${_BOOTSTRAP__YQ_BIN:-}" ]] && [[ -x "${_BOOTSTRAP__YQ_BIN}" ]] && _bootstrap__yq_compatible "${_BOOTSTRAP__YQ_BIN}"; then
    printf '%s\n' "${_BOOTSTRAP__YQ_BIN}"
    return 0
  fi
  _BOOTSTRAP__YQ_BIN=""

  # Fast path 2: compatible yq already on PATH.
  local _existing
  _existing="$(command -v yq 2> /dev/null || true)"
  if [[ -n "${_existing}" ]] && _bootstrap__yq_compatible "${_existing}"; then
    logging__skip "Compatible yq already on PATH at '${_existing}'."
    _BOOTSTRAP__YQ_BIN="${_existing}"
    printf '%s\n' "${_existing}"
    return 0
  fi

  # Fast path 3: previously bootstrapped binary still alive.
  local _state_ctx _state_path _state_group
  install__read_state "yq" _state_ctx _state_path _state_group
  if [[ -x "${_state_path:-}" ]] && _bootstrap__yq_compatible "${_state_path}"; then
    logging__skip "Reusing bootstrapped yq at '${_state_path}'."
    _BOOTSTRAP__YQ_BIN="${_state_path}"
    printf '%s\n' "${_state_path}"
    return 0
  fi

  logging__install "Bootstrapping yq (spec='${_spec}')."

  # Resolve version.
  local _resolved_ver
  logging__info "Resolving yq version for spec '${_spec}'."
  _resolved_ver="$(github__resolve_version "mikefarah/yq" "${_spec}" --version)"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to resolve yq version for spec '${_spec}'."
    return "$_rc"
  }

  local _os _arch
  _os="$(os__release_kernel)"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to detect OS kernel."
    return "$_rc"
  }
  _arch="$(os__release_arch)"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to detect CPU architecture."
    return "$_rc"
  }
  case "${_arch}" in
    amd64 | arm64) ;;
    *)
      logging__error "unsupported architecture '${_arch}'."
      return 1
      ;;
  esac

  local _base="https://github.com/mikefarah/yq/releases/download/v${_resolved_ver}"

  # Compute SHA-256 via yq's custom checksum extraction script.
  local _hdir _f _expected_hash
  _hdir="$(file__mktmpdir "bootstrap/yq-checksums")"
  logging__download "Fetching yq checksum bundle from '${_base}'."
  for _f in checksums checksums_hashes_order extract-checksum.sh; do
    net__fetch_url_file "${_base}/${_f}" "${_hdir}/${_f}"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "failed to fetch checksum file '${_f}' from '${_base}'."
      return "$_rc"
    }
  done
  _expected_hash="$(cd "${_hdir}" && shell__bash extract-checksum.sh SHA-256 "yq_${_os}_${_arch}" | awk '{print $2}')"
  if [[ ! "${_expected_hash:-}" =~ ^[0-9a-f]{64}$ ]]; then
    logging__error "invalid SHA-256 for yq_${_os}_${_arch}."
    return 1
  fi

  local _install_dir
  _install_dir="$(file__tmpdir "bootstrap/yq")"
  logging__install "Installing yq binary 'yq_${_os}_${_arch}' from '${_base}'."
  install__release_asset \
    --asset-uri "${_base}/yq_${_os}_${_arch}" \
    --sha256 "${_expected_hash}" \
    --binary-dest "${_install_dir}/yq"

  _BOOTSTRAP__YQ_BIN="${_install_dir}/yq"
  install__state_record "yq" "internal" "binary" "${_install_dir}/yq" "devfeats-bootstrap-yq" || true
  # Path is emitted by install__release_asset → uri__fetch_asset (do not printf again:
  # duplicate stdout lines break `_bin="$(bootstrap__yq)"` capture).
}

bootstrap__oras() {
  # @brief bootstrap__oras [<version-spec>] — Ensure oras is available and print its path.
  #
  # Returns an already-installed oras path when one exists on PATH.  Otherwise
  # downloads the release archive, verifies GPG signature, installs the binary to
  # a process-lifetime temp directory, and caches the result.
  #
  # Args:
  #   [version-spec]  Version spec accepted by github__resolve_version (e.g.
  #                   "stable", "latest", "1.2.3"). Defaults to "stable".
  #
  # Stdout: absolute path to the oras binary.
  # Returns: 0 on success, 1 on any failure.
  local _spec="${1:-stable}"

  # Fast path 1: oras already on PATH.
  local _existing
  _existing="$(command -v oras 2> /dev/null || true)"
  if [[ -n "${_existing}" ]]; then
    logging__skip "oras already on PATH at '${_existing}'."
    printf '%s\n' "${_existing}"
    return 0
  fi

  # Fast path 2: previously bootstrapped binary still alive.
  local _state_ctx _state_path _state_group
  install__read_state "oras" _state_ctx _state_path _state_group
  if [[ -x "${_state_path:-}" ]]; then
    logging__skip "Reusing bootstrapped oras at '${_state_path}'."
    printf '%s\n' "${_state_path}"
    return 0
  fi

  logging__install "Bootstrapping oras (spec='${_spec}')."

  # Resolve version.
  local _resolved_ver
  logging__info "Resolving oras version for spec '${_spec}'."
  _resolved_ver="$(github__resolve_version "oras-project/oras" "${_spec}" --version)"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to resolve oras version for spec '${_spec}'."
    return "$_rc"
  }

  local _os _arch
  _os="$(os__release_kernel)"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to detect OS kernel."
    return "$_rc"
  }
  _arch="$(os__release_arch)"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to detect CPU architecture."
    return "$_rc"
  }
  case "${_arch}" in
    amd64 | arm64 | armv7 | ppc64le | s390x | riscv64 | loong64) ;;
    *)
      logging__error "unsupported architecture '${_arch}'."
      return 1
      ;;
  esac

  local _tag="v${_resolved_ver}"
  local _asset="oras_${_resolved_ver}_${_os}_${_arch}.tar.gz"
  local _install_dir
  _install_dir="$(file__tmpdir "bootstrap/oras")"
  logging__install "Installing oras asset '${_asset}' from GitHub release '${_tag}'."
  install__release_asset \
    --asset-uri "https://github.com/oras-project/oras/releases/download/${_tag}/${_asset}" \
    --binary-src oras \
    --binary-dest "${_install_dir}/" \
    --gpg-key "https://raw.githubusercontent.com/oras-project/oras/refs/heads/main/KEYS"

  install__state_record "oras" "internal" "binary" "${_install_dir}/oras" "devfeats-bootstrap-oras" || true
  # Path is emitted by install__release_asset → uri__fetch_asset (see bootstrap__yq).
}

bootstrap__git() {
  # @brief bootstrap__git — Ensure git is available via the OS package manager.
  #
  # Also ensures a CA bundle is present: ospkg installs run without recommends,
  # so git can arrive without ca-certificates — and every git use in this
  # codebase is https, which then fails TLS verification ("CAfile: none").
  #
  # Returns: 0 on success, 1 on failure.
  logging__install "Ensuring git is available (ospkg tracked: lib-git)."
  ospkg__install_tracked "lib-git" git || return 1
  bootstrap__ca_certs
}

bootstrap__xcode() {
  # @brief bootstrap__xcode — Ensure Xcode Command Line Tools are installed (macOS only).
  # Thin bash wrapper around `posix__bootstrap_xcode`.
  # Returns: 0 when CLTs are present (or successfully installed), 1 on failure.
  [ "$(uname -s)" = "Darwin" ] || return 0
  posix__bootstrap_xcode
}

_bootstrap__jsonschema_compatible() {
  # @brief _bootstrap__jsonschema_compatible <bin> — Return 0 when <bin> is sourcemeta/jsonschema (supports `validate`).
  #
  # Distinguishes the sourcemeta CLI from the unrelated Python `jsonschema` package
  # (which emits deprecation warnings and uses a completely different interface).
  # The sourcemeta binary outputs a bare semver string from `version`; the Python
  # one prefixes the output with a DeprecationWarning, so the output does not
  # match the bare `X.Y.Z` pattern.
  local _bin="${1-}"
  [[ -n "$_bin" ]] || {
    logging__error "jsonschema binary path is empty."
    return 1
  }
  local _out
  _out="$("$_bin" version 2>&1)" || return 1
  # Must output a bare version like "16.0.0" — no deprecation noise.
  [[ "$_out" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

bootstrap__jsonschema() {
  # @brief bootstrap__jsonschema [<version-spec>] — Ensure sourcemeta/jsonschema is available and print its path.
  #
  # Returns the path of an already-installed compatible binary when one exists.
  # Otherwise downloads and installs the GitHub release zip via
  # `github__install_release` (which fetches the SHA-256 from the release JSON
  # automatically). Sets _BOOTSTRAP__JSONSCHEMA_BIN for callers that need the
  # path without a subshell.
  #
  # Args:
  #   [version-spec]  Version spec accepted by github__resolve_version (e.g.
  #                   "16", "latest", "16.0.0"). Defaults to "16" (latest
  #                   release in the current major line).
  #
  # Stdout: absolute path to a sourcemeta/jsonschema-compatible binary.
  # Returns: 0 on success, 1 on any failure.
  local _spec="${1:-16}"

  # Fast path 1: in-process cache.
  if [[ -n "${_BOOTSTRAP__JSONSCHEMA_BIN:-}" ]] && [[ -x "${_BOOTSTRAP__JSONSCHEMA_BIN}" ]] && _bootstrap__jsonschema_compatible "${_BOOTSTRAP__JSONSCHEMA_BIN}"; then
    printf '%s\n' "${_BOOTSTRAP__JSONSCHEMA_BIN}"
    return 0
  fi
  _BOOTSTRAP__JSONSCHEMA_BIN=""

  # Fast path 2: compatible jsonschema already on PATH.
  local _existing
  _existing="$(command -v jsonschema 2> /dev/null || true)"
  if [[ -n "${_existing}" ]] && _bootstrap__jsonschema_compatible "${_existing}"; then
    logging__skip "Compatible jsonschema already on PATH at '${_existing}'."
    _BOOTSTRAP__JSONSCHEMA_BIN="${_existing}"
    printf '%s\n' "${_existing}"
    return 0
  fi

  # Fast path 3: previously bootstrapped binary still alive.
  local _state_ctx _state_path _state_group
  install__read_state "jsonschema" _state_ctx _state_path _state_group
  if [[ -x "${_state_path:-}" ]] && _bootstrap__jsonschema_compatible "${_state_path}"; then
    logging__skip "Reusing bootstrapped jsonschema at '${_state_path}'."
    _BOOTSTRAP__JSONSCHEMA_BIN="${_state_path}"
    printf '%s\n' "${_state_path}"
    return 0
  fi

  logging__install "Bootstrapping jsonschema (spec='${_spec}')."

  # Resolve version and tag in one call (default output: tag on line 1, bare version on line 2).
  local _resolve_output _resolved_tag _resolved_ver
  logging__info "Resolving jsonschema version for spec '${_spec}'."
  _resolve_output="$(github__resolve_version "sourcemeta/jsonschema" "${_spec}")"
  local _rc=$?
  [[ $_rc == 0 && -n "${_resolve_output:-}" ]] || {
    logging__error "failed to resolve jsonschema version for spec '${_spec}'."
    return 1
  }
  _resolved_tag="${_resolve_output%%$'\n'*}"
  _resolved_ver="${_resolve_output##*$'\n'}"

  # Build asset name using ctx__expand_pattern for OS/arch substitution.
  # sourcemeta/jsonschema asset naming: jsonschema-{ver}-{os}-{arch}[-musl].zip
  # where {os} is "linux"/"darwin", {arch} is "x86_64"/"arm64" (not amd64),
  # and Alpine/musl systems need the "-musl" suffix.
  local _asset_name
  _asset_name="$(ctx__expand_pattern \
    "jsonschema-${_resolved_ver}-{plat.kernel:lower}-{plat.machine_release==amd64?x86_64:{plat.machine_release}}{plat.libc==musl?-musl:}.zip")"

  local _install_dir
  _install_dir="$(file__tmpdir "bootstrap/jsonschema")"
  logging__install "Installing sourcemeta/jsonschema '${_asset_name}' (tag: ${_resolved_tag})."
  github__install_release \
    --repo "sourcemeta/jsonschema" \
    --tag "${_resolved_tag}" \
    --asset "${_asset_name}" \
    --binary-src "bin/jsonschema" \
    --binary-dest "${_install_dir}/jsonschema"

  _BOOTSTRAP__JSONSCHEMA_BIN="${_install_dir}/jsonschema"
  install__state_record "jsonschema" "internal" "binary" "${_install_dir}/jsonschema" "devfeats-bootstrap-jsonschema" || true
  # Path is emitted by github__install_release → install__release_asset → uri__fetch_asset
  # (do not printf again: duplicate stdout lines break `_bin="$(bootstrap__jsonschema)"` capture).
}
