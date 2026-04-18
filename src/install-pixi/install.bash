#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$_SELF_DIR"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: Pixi" >&2
# Override _cleanup_hook in the hand-written section for feature-specific
# cleanup (e.g. removing temp files). Do NOT call logging__cleanup there;
# _on_exit owns that call and guarantees it runs exactly once, last.
# shellcheck disable=SC2329
_cleanup_hook() { return; }
# shellcheck disable=SC2329
_on_exit() {
  local _rc=$?
  _cleanup_hook
  [[ "${KEEP_CACHE:-true}" != true ]] && ospkg__clean
  if [[ $_rc -eq 0 ]]; then
    echo "✅ Pixi script finished successfully." >&2
  else
    echo "❌ Pixi script exited with error ${_rc}." >&2
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT

__usage__() {
  cat << 'EOF'
Usage: install.bash [OPTIONS]

Options:
  --version <value>                          Version of Pixi to install (e.g. '0.67.0'). (default: "latest")
  --prefix <value>                           Installation prefix for pixi. The 'pixi' binary is placed at '$prefix/bin/pixi'. (default: "auto")
  --if_exists {skip|fail|reinstall|update}   What to do when a pixi binary already exists at $prefix/bin. (default: "skip")
  --installer_dir <value>                    Directory to download the pixi .tar.gz archive and its .tar.gz.sha256 sidecar to. (default: "/tmp/pixi-installer")
  --arch <value>                             Override the detected CPU architecture when selecting a release asset.
  --home_dir <value>                         Set PIXI_HOME -- the directory where pixi stores global environments (pixi global install) and configuration.
  --download_url <value>                     Override the binary download URL for the pixi .tar.gz archive.
  --netrc <value>                            Path to a .netrc file for authenticating the download request.
  --export_path <value>                      Controls which shell startup files receive the PATH export for $prefix/bin. (default: "auto")
  --export_pixi_home <value>                 Controls which shell startup files receive 'export PIXI_HOME=<home_dir>'. (default: "auto")
  --symlink {true,false}                     Create a symlink from the canonical bin directory to $prefix/bin/pixi when prefix resolves to a non-default path. (default: "true")
  --shell_completions <value>  (repeatable)  Shell names to write pixi completion eval blocks for.
  --keep_installer {true,false}              Keep the downloaded .tar.gz archive and .tar.gz.sha256 sidecar file after installation. (default: "false")
  --keep_cache {true,false}                  Keep the package manager cache after installation. By default, the package manager cache is removed after installation to reduce image layer size. Set this flag to true to keep the cache, which may speed up subsequent installations at the cost of larger image layers. (default: "false")
  --debug {true,false}                       Enable debug output. This adds `set -x` to the installer script, which prints each command before executing it. (default: "false")
  --logfile <value>                          Log all output (stdout + stderr) to this file in addition to console.
  -h, --help                                 Show this help
EOF
  return
}

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  VERSION="latest"
  PREFIX="auto"
  IF_EXISTS="skip"
  INSTALLER_DIR="/tmp/pixi-installer"
  ARCH=""
  HOME_DIR=""
  DOWNLOAD_URL=""
  NETRC=""
  EXPORT_PATH="auto"
  EXPORT_PIXI_HOME="auto"
  SYMLINK=true
  SHELL_COMPLETIONS=()
  KEEP_INSTALLER=false
  KEEP_CACHE=false
  DEBUG=false
  LOGFILE=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --version)
        shift
        VERSION="$1"
        echo "📩 Read argument 'version': '${VERSION}'" >&2
        shift
        ;;
      --prefix)
        shift
        PREFIX="$1"
        echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
        shift
        ;;
      --if_exists)
        shift
        IF_EXISTS="$1"
        echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
        shift
        ;;
      --installer_dir)
        shift
        INSTALLER_DIR="$1"
        echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
        shift
        ;;
      --arch)
        shift
        ARCH="$1"
        echo "📩 Read argument 'arch': '${ARCH}'" >&2
        shift
        ;;
      --home_dir)
        shift
        HOME_DIR="$1"
        echo "📩 Read argument 'home_dir': '${HOME_DIR}'" >&2
        shift
        ;;
      --download_url)
        shift
        DOWNLOAD_URL="$1"
        echo "📩 Read argument 'download_url': '${DOWNLOAD_URL}'" >&2
        shift
        ;;
      --netrc)
        shift
        NETRC="$1"
        echo "📩 Read argument 'netrc': '${NETRC}'" >&2
        shift
        ;;
      --export_path)
        shift
        EXPORT_PATH="$1"
        echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
        shift
        ;;
      --export_pixi_home)
        shift
        EXPORT_PIXI_HOME="$1"
        echo "📩 Read argument 'export_pixi_home': '${EXPORT_PIXI_HOME}'" >&2
        shift
        ;;
      --symlink)
        shift
        SYMLINK="$1"
        echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
        shift
        ;;
      --shell_completions)
        shift
        SHELL_COMPLETIONS+=("$1")
        echo "📩 Read argument 'shell_completions': '$1'" >&2
        shift
        ;;
      --keep_installer)
        shift
        KEEP_INSTALLER="$1"
        echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2
        shift
        ;;
      --keep_cache)
        shift
        KEEP_CACHE="$1"
        echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
        shift
        ;;
      --debug)
        shift
        DEBUG="$1"
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      -h | --help)
        __usage__
        exit 0
        ;;
      --*)
        echo "⛔ Unknown option: '${1}'" >&2
        exit 1
        ;;
      *)
        echo "⛔ Unexpected argument: '${1}'" >&2
        exit 1
        ;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${VERSION+defined}" ] && echo "📩 Read argument 'version': '${VERSION}'" >&2
  [ "${PREFIX+defined}" ] && echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
  [ "${IF_EXISTS+defined}" ] && echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
  [ "${INSTALLER_DIR+defined}" ] && echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
  [ "${ARCH+defined}" ] && echo "📩 Read argument 'arch': '${ARCH}'" >&2
  [ "${HOME_DIR+defined}" ] && echo "📩 Read argument 'home_dir': '${HOME_DIR}'" >&2
  [ "${DOWNLOAD_URL+defined}" ] && echo "📩 Read argument 'download_url': '${DOWNLOAD_URL}'" >&2
  [ "${NETRC+defined}" ] && echo "📩 Read argument 'netrc': '${NETRC}'" >&2
  [ "${EXPORT_PATH+defined}" ] && echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
  [ "${EXPORT_PIXI_HOME+defined}" ] && echo "📩 Read argument 'export_pixi_home': '${EXPORT_PIXI_HOME}'" >&2
  [ "${SYMLINK+defined}" ] && echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
  if [ "${SHELL_COMPLETIONS+defined}" ]; then
    if [ -n "${SHELL_COMPLETIONS-}" ]; then
      mapfile -t SHELL_COMPLETIONS < <(printf '%s\n' "${SHELL_COMPLETIONS}" | grep -v '^$')
      for _item in "${SHELL_COMPLETIONS[@]}"; do
        echo "📩 Read argument 'shell_completions': '$_item'" >&2
      done
    else
      SHELL_COMPLETIONS=()
    fi
  fi
  [ "${KEEP_INSTALLER+defined}" ] && echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2
  [ "${KEEP_CACHE+defined}" ] && echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${VERSION+defined}" ] || {
  VERSION="latest"
  echo "ℹ️ Argument 'version' set to default value 'latest'." >&2
}
[ "${PREFIX+defined}" ] || {
  PREFIX="auto"
  echo "ℹ️ Argument 'prefix' set to default value 'auto'." >&2
}
[ "${IF_EXISTS+defined}" ] || {
  IF_EXISTS="skip"
  echo "ℹ️ Argument 'if_exists' set to default value 'skip'." >&2
}
[ "${INSTALLER_DIR+defined}" ] || {
  INSTALLER_DIR="/tmp/pixi-installer"
  echo "ℹ️ Argument 'installer_dir' set to default value '/tmp/pixi-installer'." >&2
}
[ "${ARCH+defined}" ] || {
  ARCH=""
  echo "ℹ️ Argument 'arch' set to default value ''." >&2
}
[ "${HOME_DIR+defined}" ] || {
  HOME_DIR=""
  echo "ℹ️ Argument 'home_dir' set to default value ''." >&2
}
[ "${DOWNLOAD_URL+defined}" ] || {
  DOWNLOAD_URL=""
  echo "ℹ️ Argument 'download_url' set to default value ''." >&2
}
[ "${NETRC+defined}" ] || {
  NETRC=""
  echo "ℹ️ Argument 'netrc' set to default value ''." >&2
}
[ "${EXPORT_PATH+defined}" ] || {
  EXPORT_PATH="auto"
  echo "ℹ️ Argument 'export_path' set to default value 'auto'." >&2
}
[ "${EXPORT_PIXI_HOME+defined}" ] || {
  EXPORT_PIXI_HOME="auto"
  echo "ℹ️ Argument 'export_pixi_home' set to default value 'auto'." >&2
}
[ "${SYMLINK+defined}" ] || {
  SYMLINK=true
  echo "ℹ️ Argument 'symlink' set to default value 'true'." >&2
}
[ "${SHELL_COMPLETIONS+defined}" ] || {
  SHELL_COMPLETIONS=()
  echo "ℹ️ Argument 'shell_completions' set to default value '(empty)'." >&2
}
[ "${KEEP_INSTALLER+defined}" ] || {
  KEEP_INSTALLER=false
  echo "ℹ️ Argument 'keep_installer' set to default value 'false'." >&2
}
[ "${KEEP_CACHE+defined}" ] || {
  KEEP_CACHE=false
  echo "ℹ️ Argument 'keep_cache' set to default value 'false'." >&2
}
[ "${DEBUG+defined}" ] || {
  DEBUG=false
  echo "ℹ️ Argument 'debug' set to default value 'false'." >&2
}
[ "${LOGFILE+defined}" ] || {
  LOGFILE=""
  echo "ℹ️ Argument 'logfile' set to default value ''." >&2
}

# Validate enum options.
case "${IF_EXISTS}" in
  skip | fail | reinstall | update) ;;
  *)
    echo "⛔ Invalid value for 'if_exists': '${IF_EXISTS}' (expected: skip, fail, reinstall, update)" >&2
    exit 1
    ;;
esac

ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed

# END OF AUTOGENERATED BLOCK

# ── Function definitions ──────────────────────────────────────────────────────
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

_cleanup_hook() {
  echo "↪️ Function entry: _cleanup_hook" >&2
  if [ "${KEEP_INSTALLER:-false}" != "true" ]; then
    [ -f "${ARCHIVE:-}" ] && {
      echo "🗑 Removing archive '${ARCHIVE}'" >&2
      rm -f "${ARCHIVE}"
    }
    [ -f "${SIDECAR:-}" ] && {
      echo "🗑 Removing sidecar '${SIDECAR}'" >&2
      rm -f "${SIDECAR}"
    }
    [ -d "${INSTALLER_DIR:-}" ] && [ -z "$(ls -A "${INSTALLER_DIR:-}")" ] && {
      echo "🗑 Removing empty installer directory '${INSTALLER_DIR}'" >&2
      rmdir "${INSTALLER_DIR}"
    }
  fi
  echo "↩️ Function exit: _cleanup_hook" >&2
}

resolve_bin_dir() {
  echo "↪️ Function entry: resolve_bin_dir" >&2
  case "${PREFIX}" in
    auto)
      if [ "$(id -u)" = "0" ]; then
        PREFIX="/usr/local"
      else
        PREFIX="${HOME}/.pixi"
      fi
      ;;
    "")
      PREFIX="${HOME}/.pixi"
      ;;
    *) ;; # explicit value: use as-is
  esac
  echo "ℹ️ Resolved prefix to '${PREFIX}'" >&2
  echo "↩️ Function exit: resolve_bin_dir" >&2
  return 0
}

check_root_requirement() {
  echo "↪️ Function entry: check_root_requirement" >&2
  case "${PREFIX}" in
    /opt/* | /usr/* | /var/* | /srv/* | /snap/*)
      os__require_root
      ;;
    *)
      echo "ℹ️ Root not required for prefix '${PREFIX}'." >&2
      ;;
  esac
  echo "↩️ Function exit: check_root_requirement" >&2
  return 0
}

resolve_pixi_version() {
  echo "↪️ Function entry: resolve_pixi_version" >&2
  if [ "${VERSION}" = "latest" ]; then
    local _tag
    _tag="$(github__latest_tag "prefix-dev/pixi")" || {
      echo "⛔ Failed to fetch latest pixi tag from GitHub." >&2
      exit 1
    }
    VERSION="${_tag#v}"
    echo "ℹ️ Resolved 'latest' to version '${VERSION}'" >&2
  else
    VERSION="${VERSION#v}"
    # Validate: must be strict semver — X.Y or X.Y.Z with only digits and dots.
    if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      echo "⛔ Unrecognised version string '${VERSION}'. Expected X.Y or X.Y.Z (with or without leading v)." >&2
      exit 1
    fi
  fi
  echo "↩️ Function exit: resolve_pixi_version" >&2
  return 0
}

detect_triple() {
  echo "↪️ Function entry: detect_triple" >&2
  local _kernel _arch
  _kernel="$(os__kernel)"
  _arch="${ARCH:-$(os__arch)}"
  case "${_kernel}/${_arch}" in
    Linux/x86_64) TRIPLE="x86_64-unknown-linux-musl" ;;
    Linux/aarch64) TRIPLE="aarch64-unknown-linux-musl" ;;
    Linux/riscv64) TRIPLE="riscv64gc-unknown-linux-gnu" ;;
    Darwin/x86_64) TRIPLE="x86_64-apple-darwin" ;;
    Darwin/aarch64) TRIPLE="aarch64-apple-darwin" ;;
    *)
      echo "⛔ Unsupported platform: kernel='${_kernel}' arch='${_arch}'" >&2
      exit 1
      ;;
  esac
  echo "ℹ️ Detected release triple: '${TRIPLE}'" >&2
  echo "↩️ Function exit: detect_triple" >&2
  return 0
}

resolve_installer_paths() {
  echo "↪️ Function entry: resolve_installer_paths" >&2
  if [ -n "${DOWNLOAD_URL}" ]; then
    ARCHIVE_URL="${DOWNLOAD_URL}"
    SIDECAR_URL=""
    ARCHIVE="${INSTALLER_DIR}/pixi-custom.tar.gz"
    SIDECAR=""
    echo "ℹ️ Using custom download URL; checksum verification will be skipped." >&2
  else
    ARCHIVE_URL="https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TRIPLE}.tar.gz"
    SIDECAR_URL="https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TRIPLE}.tar.gz.sha256"
    ARCHIVE="${INSTALLER_DIR}/pixi-${TRIPLE}.tar.gz"
    SIDECAR="${INSTALLER_DIR}/pixi-${TRIPLE}.tar.gz.sha256"
  fi
  echo "ℹ️ Archive URL: '${ARCHIVE_URL}'" >&2
  echo "↩️ Function exit: resolve_installer_paths" >&2
  return 0
}

download_pixi() {
  echo "↪️ Function entry: download_pixi" >&2
  mkdir -p "${INSTALLER_DIR}"
  echo "📥 Downloading pixi archive from '${ARCHIVE_URL}'" >&2
  if [ -n "${NETRC}" ]; then
    if command -v curl > /dev/null 2>&1; then
      curl --fail --location --retry 3 \
        --netrc-file "${NETRC}" --output "${ARCHIVE}" "${ARCHIVE_URL}"
    elif command -v wget > /dev/null 2>&1; then
      wget --tries=3 --auth-no-challenge \
        --netrc-file "${NETRC}" --output-document "${ARCHIVE}" "${ARCHIVE_URL}"
    else
      echo "⛔ Neither curl nor wget is available." >&2
      exit 1
    fi
  else
    net__fetch_url_file "${ARCHIVE_URL}" "${ARCHIVE}"
  fi
  if [ -n "${SIDECAR_URL:-}" ]; then
    echo "📥 Downloading checksum sidecar from '${SIDECAR_URL}'" >&2
    net__fetch_url_file "${SIDECAR_URL}" "${SIDECAR}"
  fi
  echo "↩️ Function exit: download_pixi" >&2
  return 0
}

verify_pixi() {
  echo "↪️ Function entry: verify_pixi" >&2
  if [ -z "${SIDECAR_URL:-}" ]; then
    echo "⚠️ Checksum verification skipped (custom download_url set; ensure your source is trusted)." >&2
    echo "↩️ Function exit: verify_pixi" >&2
    return 0
  fi
  echo "🔍 Verifying SHA-256 checksum..." >&2
  checksum__verify_sha256_sidecar "${ARCHIVE}" "${SIDECAR}"
  echo "✅ Checksum verified." >&2
  echo "↩️ Function exit: verify_pixi" >&2
  return 0
}

# get_installed_version — prints bare semver (no v prefix) to stdout, or empty string.
get_installed_version() {
  local _bin="${PREFIX}/bin/pixi"
  if [ -x "${_bin}" ]; then
    "${_bin}" --version 2> /dev/null | awk '{print $NF}' | sed 's/^v//' || true
    return 0
  fi
  if command -v pixi > /dev/null 2>&1; then
    pixi --version 2> /dev/null | awk '{print $NF}' | sed 's/^v//' || true
    return 0
  fi
  echo ""
  return 0
}

handle_if_exists() {
  echo "↪️ Function entry: handle_if_exists" >&2
  case "${IF_EXISTS}" in
    skip)
      echo "ℹ️ pixi already installed — skipping install (if_exists=skip)." >&2
      _SKIP_INSTALL=true
      ;;
    fail)
      echo "⛔ pixi already installed and if_exists=fail." >&2
      exit 1
      ;;
    reinstall)
      echo "🗑 Removing existing pixi binary at '${PREFIX}/bin/pixi'..." >&2
      rm -f "${PREFIX}/bin/pixi"
      _SKIP_INSTALL=false
      ;;
    update)
      update_pixi
      _SKIP_INSTALL=true
      ;;
  esac
  echo "↩️ Function exit: handle_if_exists" >&2
  return 0
}

update_pixi() {
  echo "↪️ Function entry: update_pixi" >&2
  local _pixi_bin
  if [ -x "${PREFIX}/bin/pixi" ]; then
    _pixi_bin="${PREFIX}/bin/pixi"
  elif command -v pixi > /dev/null 2>&1; then
    _pixi_bin="$(command -v pixi)"
  else
    echo "⛔ Cannot find pixi binary for self-update." >&2
    exit 1
  fi
  echo "⬆️ Updating pixi via self-update to version '${VERSION}'..." >&2
  "${_pixi_bin}" self-update --version "${VERSION}"
  echo "↩️ Function exit: update_pixi" >&2
  return 0
}

install_pixi_binary() {
  echo "↪️ Function entry: install_pixi_binary" >&2
  local _tmpdir="${INSTALLER_DIR}/_extract"
  mkdir -p "${PREFIX}/bin" "${_tmpdir}"
  echo "📦 Extracting archive to '${PREFIX}/bin/pixi'..." >&2
  tar -xzf "${ARCHIVE}" -C "${_tmpdir}"
  mv "${_tmpdir}/pixi" "${PREFIX}/bin/pixi"
  chmod 0755 "${PREFIX}/bin/pixi"
  rm -rf "${_tmpdir}"
  echo "✅ pixi binary installed to '${PREFIX}/bin/pixi'" >&2
  echo "↩️ Function exit: install_pixi_binary" >&2
  return 0
}

create_symlink() {
  echo "↪️ Function entry: create_symlink" >&2
  if [ "${SYMLINK}" != "true" ]; then
    echo "ℹ️ symlink=false; skipping symlink creation." >&2
    echo "↩️ Function exit: create_symlink" >&2
    return 0
  fi
  shell__create_symlink \
    --src "${PREFIX}/bin/pixi" \
    --system-target "/usr/local/bin/pixi" \
    --user-target "${HOME}/.pixi/bin/pixi"
  echo "↩️ Function exit: create_symlink" >&2
  return 0
}

verify_installed_binary() {
  echo "↪️ Function entry: verify_installed_binary" >&2
  local _ver=""
  if "${PREFIX}/bin/pixi" --version > /dev/null 2>&1; then
    _ver="$("${PREFIX}/bin/pixi" --version 2> /dev/null)"
  elif command -v pixi > /dev/null 2>&1; then
    _ver="$(pixi --version 2> /dev/null)"
  else
    echo "⛔ pixi not found at '${PREFIX}/bin/pixi' and not on PATH." >&2
    exit 1
  fi
  echo "ℹ️ Verified pixi: ${_ver}" >&2
  echo "↩️ Function exit: verify_installed_binary" >&2
  return 0
}

export_path_main() {
  echo "↪️ Function entry: export_path_main" >&2
  if [ "${EXPORT_PATH}" = "" ]; then
    echo "ℹ️ export_path is empty; skipping PATH export." >&2
    echo "↩️ Function exit: export_path_main" >&2
    return 0
  fi
  if [ "${EXPORT_PATH}" = "auto" ] && [ "${PREFIX}" = "/usr/local" ]; then
    echo "ℹ️ PREFIX is /usr/local which is already on PATH in all container images; skipping PATH write." >&2
    echo "↩️ Function exit: export_path_main" >&2
    return 0
  fi
  local _content="export PATH=\"${PREFIX}/bin:\${PATH}\""
  local _marker="pixi PATH (install-pixi)"
  local _target_files
  if [ "${EXPORT_PATH}" != "auto" ]; then
    _target_files="${EXPORT_PATH}"
  else
    if [ "$(id -u)" = "0" ]; then
      echo "ℹ️ System-wide PATH export (root)." >&2
      _target_files="$(shell__system_path_files --profile_d "pixi_bin_path.sh")"
    else
      echo "ℹ️ User-scoped PATH export (non-root)." >&2
      # shellcheck disable=SC2119
      _target_files="$(shell__user_path_files)"
    fi
  fi
  shell__sync_block --files "${_target_files}" --marker "${_marker}" --content "${_content}"
  echo "↩️ Function exit: export_path_main" >&2
  return 0
}

export_pixi_home_main() {
  echo "↪️ Function entry: export_pixi_home_main" >&2
  if [ -z "${HOME_DIR}" ]; then
    echo "ℹ️ home_dir is empty; skipping PIXI_HOME export." >&2
    echo "↩️ Function exit: export_pixi_home_main" >&2
    return 0
  fi
  if [ "${EXPORT_PIXI_HOME}" = "" ]; then
    echo "ℹ️ export_pixi_home is empty; skipping PIXI_HOME export." >&2
    echo "↩️ Function exit: export_pixi_home_main" >&2
    return 0
  fi
  local _content="export PIXI_HOME=\"${HOME_DIR}\""
  local _marker="pixi PIXI_HOME (install-pixi)"
  local _target_files
  if [ "${EXPORT_PIXI_HOME}" != "auto" ]; then
    _target_files="${EXPORT_PIXI_HOME}"
  else
    if [ "$(id -u)" = "0" ]; then
      echo "ℹ️ System-wide PIXI_HOME export (root)." >&2
      _target_files="$(shell__system_path_files --profile_d "pixi_home.sh")"
    else
      echo "ℹ️ User-scoped PIXI_HOME export (non-root)." >&2
      # shellcheck disable=SC2119
      _target_files="$(shell__user_path_files)"
    fi
  fi
  shell__sync_block --files "${_target_files}" --marker "${_marker}" --content "${_content}"
  echo "↩️ Function exit: export_pixi_home_main" >&2
  return 0
}

install_completion() {
  echo "↪️ Function entry: install_completion" >&2
  if [ "${#SHELL_COMPLETIONS[@]}" -eq 0 ]; then
    echo "ℹ️ shell_completions is empty; skipping completion install." >&2
    echo "↩️ Function exit: install_completion" >&2
    return 0
  fi
  local _marker="pixi completion (install-pixi)"
  local _shell
  for _shell in "${SHELL_COMPLETIONS[@]}"; do
    local _content="eval \"\$(pixi completion --shell ${_shell})\""
    local _target_file
    case "${_shell}" in
      bash)
        if [ "$(id -u)" = "0" ]; then
          _target_file="$(shell__detect_bashrc)"
        else
          _target_file="${HOME}/.bashrc"
        fi
        ;;
      zsh)
        if [ "$(id -u)" = "0" ]; then
          _target_file="$(shell__detect_zshdir)/zshenv"
        else
          _target_file="${HOME}/.zshenv"
        fi
        ;;
      fish)
        _target_file="${HOME}/.config/fish/config.fish"
        ;;
      nushell)
        _target_file="${HOME}/.config/nushell/config.nu"
        ;;
      elvish)
        _target_file="${HOME}/.config/elvish/rc.elv"
        ;;
      *)
        echo "⛔ Unsupported shell: '${_shell}' (expected: bash, zsh, fish, nushell, elvish)" >&2
        exit 1
        ;;
    esac
    mkdir -p "$(dirname "${_target_file}")"
    [ -f "${_target_file}" ] || touch "${_target_file}"
    shell__write_block --file "${_target_file}" --marker "${_marker}" --content "${_content}"
    echo "✅ Shell completion for '${_shell}' written to '${_target_file}'" >&2
  done
  echo "↩️ Function exit: install_completion" >&2
  return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────

# shellcheck source=lib/shell.sh
. "${_SELF_DIR}/_lib/shell.sh"
# shellcheck source=lib/github.sh
. "${_SELF_DIR}/_lib/github.sh"
# shellcheck source=lib/checksum.sh
. "${_SELF_DIR}/_lib/checksum.sh"

resolve_bin_dir
check_root_requirement
resolve_pixi_version

# Version-match idempotency check: only compare against the requested install
# target (PREFIX/bin/pixi).  A pixi reachable only via PATH at a different location
# does NOT satisfy the target — we still need to install there.
_INSTALLED_VER=""
if [ -x "${PREFIX}/bin/pixi" ]; then
  _INSTALLED_VER="$(get_installed_version)"
fi
_SKIP_INSTALL=false
if [ -n "${_INSTALLED_VER}" ] && [ "${_INSTALLED_VER}" = "${VERSION}" ]; then
  echo "ℹ️ Installed pixi version '${_INSTALLED_VER}' matches '${VERSION}'. Skipping install." >&2
  _SKIP_INSTALL=true
elif [ -x "${PREFIX}/bin/pixi" ]; then
  # A different version is already at the requested install target: apply policy.
  handle_if_exists
fi

if [ "${_SKIP_INSTALL}" != "true" ]; then
  detect_triple
  resolve_installer_paths
  download_pixi
  verify_pixi
  install_pixi_binary
fi

verify_installed_binary
create_symlink
export_path_main
export_pixi_home_main
install_completion
