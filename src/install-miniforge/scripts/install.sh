#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: Miniforge Installer" >&2
# Override _cleanup_hook in the hand-written section for feature-specific
# cleanup (e.g. removing temp files). Do NOT call logging__cleanup there;
# _on_exit owns that call and guarantees it runs exactly once, last.
# shellcheck disable=SC2329
_cleanup_hook() { return; }
# shellcheck disable=SC2329
_on_exit() {
  local _rc=$?
  _cleanup_hook
  if [[ $_rc -eq 0 ]]; then
    echo "✅ Miniforge Installer script finished successfully." >&2
  else
    echo "❌ Miniforge Installer script exited with error ${_rc}." >&2
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT

__usage__() {
  cat << 'EOF'
Usage: install.sh [OPTIONS]

Options:
  --version <value>                          Conda version to install (e.g. '26.3.1'). (default: "latest")
  --if_exists {skip|fail|reinstall|update}   What to do when conda is already installed at prefix. (default: "skip")
  --preserve_envs {true,false}               When if_exists is 'reinstall', export all non-base conda environments before (default: "true")
  --preserve_config {true,false}             When if_exists is 'reinstall', skip conda init --reverse and preserve .condarc (default: "true")
  --update_base {true,false}                 Update the base conda environment. (default: "false")
  --prefix <value>                           Path to the conda installation directory (installation root/prefix). (default: "auto")
  --export_path <value>                      Controls which shell startup files receive the PATH export for $PREFIX/bin. (default: "auto")
  --symlink {true,false}                     Create a directory symlink from the canonical conda prefix to $prefix when prefix resolves to a non-default path. (default: "true")
  --shell_activations <value>  (repeatable)  Shell names to write conda initialization blocks for.
  --activate_env <value>                     Conda environment to activate at shell startup. (default: "base")
  --write_group <value>                      OS group for shared write access to the conda prefix. (default: "conda")
  --add_current_user {true,false}            Include the current user (the user running the installer, or SUDO_USER if set) in the resolved user list for per-user config writes and write-permission group membership. (default: "true")
  --add_remote_user {true,false}             Include the devcontainer remoteUser (from the _REMOTE_USER env var) in the resolved user list for per-user config writes and write-permission group membership. (default: "true")
  --add_container_user {true,false}          Include the devcontainer containerUser (from the _CONTAINER_USER env var) in the resolved user list for per-user config writes and write-permission group membership. (default: "true")
  --add_users <value>  (repeatable)          Additional usernames to include in the resolved user list for per-user config writes and write-permission group membership.
  --interactive {true,false}                 Run the installer in interactive mode. (default: "false")
  --installer_dir <value>                    Path to a directory to download the installer to. (default: "/tmp/miniforge-installer")
  --keep_installer {true,false}              Keep the Miniforge installer script and checksum after installation instead of removing them. (default: "false")
  --debug {true,false}                       Enable debug output. (default: "false")
  --logfile <value>                          Log all output (stdout + stderr) to this file in addition to console.
  -h, --help                                 Show this help
EOF
  return
}

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  VERSION="latest"
  IF_EXISTS="skip"
  PRESERVE_ENVS=true
  PRESERVE_CONFIG=true
  UPDATE_BASE=false
  PREFIX="auto"
  EXPORT_PATH="auto"
  SYMLINK=true
  SHELL_ACTIVATIONS=()
  ACTIVATE_ENV="base"
  WRITE_GROUP="conda"
  ADD_CURRENT_USER=true
  ADD_REMOTE_USER=true
  ADD_CONTAINER_USER=true
  ADD_USERS=()
  INTERACTIVE=false
  INSTALLER_DIR="/tmp/miniforge-installer"
  KEEP_INSTALLER=false
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
      --if_exists)
        shift
        IF_EXISTS="$1"
        echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
        shift
        ;;
      --preserve_envs)
        shift
        PRESERVE_ENVS="$1"
        echo "📩 Read argument 'preserve_envs': '${PRESERVE_ENVS}'" >&2
        shift
        ;;
      --preserve_config)
        shift
        PRESERVE_CONFIG="$1"
        echo "📩 Read argument 'preserve_config': '${PRESERVE_CONFIG}'" >&2
        shift
        ;;
      --update_base)
        shift
        UPDATE_BASE="$1"
        echo "📩 Read argument 'update_base': '${UPDATE_BASE}'" >&2
        shift
        ;;
      --prefix)
        shift
        PREFIX="$1"
        echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
        shift
        ;;
      --export_path)
        shift
        EXPORT_PATH="$1"
        echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
        shift
        ;;
      --symlink)
        shift
        SYMLINK="$1"
        echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
        shift
        ;;
      --shell_activations)
        shift
        SHELL_ACTIVATIONS+=("$1")
        echo "📩 Read argument 'shell_activations': '$1'" >&2
        shift
        ;;
      --activate_env)
        shift
        ACTIVATE_ENV="$1"
        echo "📩 Read argument 'activate_env': '${ACTIVATE_ENV}'" >&2
        shift
        ;;
      --write_group)
        shift
        WRITE_GROUP="$1"
        echo "📩 Read argument 'write_group': '${WRITE_GROUP}'" >&2
        shift
        ;;
      --add_current_user)
        shift
        ADD_CURRENT_USER="$1"
        echo "📩 Read argument 'add_current_user': '${ADD_CURRENT_USER}'" >&2
        shift
        ;;
      --add_remote_user)
        shift
        ADD_REMOTE_USER="$1"
        echo "📩 Read argument 'add_remote_user': '${ADD_REMOTE_USER}'" >&2
        shift
        ;;
      --add_container_user)
        shift
        ADD_CONTAINER_USER="$1"
        echo "📩 Read argument 'add_container_user': '${ADD_CONTAINER_USER}'" >&2
        shift
        ;;
      --add_users)
        shift
        ADD_USERS+=("$1")
        echo "📩 Read argument 'add_users': '$1'" >&2
        shift
        ;;
      --interactive)
        shift
        INTERACTIVE="$1"
        echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
        shift
        ;;
      --installer_dir)
        shift
        INSTALLER_DIR="$1"
        echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
        shift
        ;;
      --keep_installer)
        shift
        KEEP_INSTALLER="$1"
        echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2
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
  [ "${IF_EXISTS+defined}" ] && echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
  [ "${PRESERVE_ENVS+defined}" ] && echo "📩 Read argument 'preserve_envs': '${PRESERVE_ENVS}'" >&2
  [ "${PRESERVE_CONFIG+defined}" ] && echo "📩 Read argument 'preserve_config': '${PRESERVE_CONFIG}'" >&2
  [ "${UPDATE_BASE+defined}" ] && echo "📩 Read argument 'update_base': '${UPDATE_BASE}'" >&2
  [ "${PREFIX+defined}" ] && echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
  [ "${EXPORT_PATH+defined}" ] && echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
  [ "${SYMLINK+defined}" ] && echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
  if [ "${SHELL_ACTIVATIONS+defined}" ]; then
    if [ -n "${SHELL_ACTIVATIONS-}" ]; then
      mapfile -t SHELL_ACTIVATIONS < <(printf '%s\n' "${SHELL_ACTIVATIONS}" | grep -v '^$')
      for _item in "${SHELL_ACTIVATIONS[@]}"; do
        echo "📩 Read argument 'shell_activations': '$_item'" >&2
      done
    else
      SHELL_ACTIVATIONS=()
    fi
  fi
  [ "${ACTIVATE_ENV+defined}" ] && echo "📩 Read argument 'activate_env': '${ACTIVATE_ENV}'" >&2
  [ "${WRITE_GROUP+defined}" ] && echo "📩 Read argument 'write_group': '${WRITE_GROUP}'" >&2
  [ "${ADD_CURRENT_USER+defined}" ] && echo "📩 Read argument 'add_current_user': '${ADD_CURRENT_USER}'" >&2
  [ "${ADD_REMOTE_USER+defined}" ] && echo "📩 Read argument 'add_remote_user': '${ADD_REMOTE_USER}'" >&2
  [ "${ADD_CONTAINER_USER+defined}" ] && echo "📩 Read argument 'add_container_user': '${ADD_CONTAINER_USER}'" >&2
  if [ "${ADD_USERS+defined}" ]; then
    if [ -n "${ADD_USERS-}" ]; then
      mapfile -t ADD_USERS < <(printf '%s\n' "${ADD_USERS}" | grep -v '^$')
      for _item in "${ADD_USERS[@]}"; do
        echo "📩 Read argument 'add_users': '$_item'" >&2
      done
    else
      ADD_USERS=()
    fi
  fi
  [ "${INTERACTIVE+defined}" ] && echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
  [ "${INSTALLER_DIR+defined}" ] && echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
  [ "${KEEP_INSTALLER+defined}" ] && echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${VERSION+defined}" ] || VERSION="latest"
[ "${IF_EXISTS+defined}" ] || IF_EXISTS="skip"
[ "${PRESERVE_ENVS+defined}" ] || PRESERVE_ENVS=true
[ "${PRESERVE_CONFIG+defined}" ] || PRESERVE_CONFIG=true
[ "${UPDATE_BASE+defined}" ] || UPDATE_BASE=false
[ "${PREFIX+defined}" ] || PREFIX="auto"
[ "${EXPORT_PATH+defined}" ] || EXPORT_PATH="auto"
[ "${SYMLINK+defined}" ] || SYMLINK=true
[ "${SHELL_ACTIVATIONS+defined}" ] || mapfile -t SHELL_ACTIVATIONS < <(printf '%s' $'bash\nzsh' | grep -v '^$')
[ "${ACTIVATE_ENV+defined}" ] || ACTIVATE_ENV="base"
[ "${WRITE_GROUP+defined}" ] || WRITE_GROUP="conda"
[ "${ADD_CURRENT_USER+defined}" ] || ADD_CURRENT_USER=true
[ "${ADD_REMOTE_USER+defined}" ] || ADD_REMOTE_USER=true
[ "${ADD_CONTAINER_USER+defined}" ] || ADD_CONTAINER_USER=true
[ "${ADD_USERS+defined}" ] || ADD_USERS=()
[ "${INTERACTIVE+defined}" ] || INTERACTIVE=false
[ "${INSTALLER_DIR+defined}" ] || INSTALLER_DIR="/tmp/miniforge-installer"
[ "${KEEP_INSTALLER+defined}" ] || KEEP_INSTALLER=false
[ "${DEBUG+defined}" ] || DEBUG=false
[ "${LOGFILE+defined}" ] || LOGFILE=""

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

if [ -z "${PREFIX-}" ] || [ "${PREFIX}" = "auto" ]; then
  if [ "$(id -u)" = "0" ]; then
    PREFIX="/opt/conda"
  else
    PREFIX="${HOME}/miniforge3"
  fi
  echo "ℹ️ Argument 'PREFIX' resolved from 'auto' to '${PREFIX}'." >&2
fi

# _conda_init_snippet <shell>
# Runs `conda init <shell>` into a tmpdir with a clean HOME and prints the
# full content of the rc file conda wrote (including conda's own markers).
# Returns empty string if conda init fails or writes nothing.
_conda_init_snippet() {
  local _shell="$1"
  local _tmpdir _f
  _tmpdir="$(mktemp -d)"
  HOME="$_tmpdir" "$CONDA_EXEC" init "$_shell" -q 2> /dev/null || true
  for _f in "$_tmpdir"/.bashrc "$_tmpdir"/.bash_profile \
    "$_tmpdir"/.zshrc "$_tmpdir"/.zprofile; do
    if [[ -f "$_f" && -s "$_f" ]]; then
      cat "$_f"
      rm -rf "$_tmpdir"
      return 0
    fi
  done
  rm -rf "$_tmpdir"
  return 0
}

add_activation_to_rcfile() {
  echo "↪️ Function entry: add_activation_to_rcfile" >&2
  if [[ -z "$SHELL_ACTIVATIONS" ]]; then
    echo "ℹ️ shell_activations is empty; skipping conda init." >&2
    echo "↩️ Function exit: add_activation_to_rcfile" >&2
    return 0
  fi
  local _shell
  for _shell in ${SHELL_ACTIVATIONS}; do
    local _target_file
    case "$_shell" in
      bash)
        if [[ "$(id -u)" == "0" ]]; then
          _target_file="$(shell__detect_bashrc)"
        else
          _target_file="${HOME}/.bashrc"
        fi
        ;;
      zsh)
        if [[ "$(id -u)" == "0" ]]; then
          _target_file="$(shell__detect_zshdir)/zshrc"
        else
          local _zdotdir
          _zdotdir="$(shell__detect_zdotdir --home "${HOME}")"
          _target_file="${_zdotdir}/.zshrc"
        fi
        ;;
      *)
        echo "⛔ Unsupported shell for conda activation: '${_shell}' (supported: bash, zsh)" >&2
        exit 1
        ;;
    esac
    echo "ℹ️ Capturing conda init snippet for ${_shell}..." >&2
    local _snippet
    _snippet="$(_conda_init_snippet "$_shell")"
    if [[ -z "$_snippet" ]]; then
      echo "⚠️ conda init produced no output for '${_shell}'; skipping." >&2
      continue
    fi
    # Optionally append conda activate after the conda init block.
    local _content="$_snippet"
    if [[ -n "${ACTIVATE_ENV:-}" && "$ACTIVATE_ENV" != "base" ]]; then
      _content="${_content}"$'\n'"conda activate ${ACTIVATE_ENV}"
    fi
    # Our marker is distinct from conda's "# >>> conda initialize >>>",
    # so shell__write_block handles idempotency without touching conda's markers.
    shell__write_block --file "$_target_file" --marker "conda init (install-miniforge)" \
      --content "$_content"
  done
  echo "↩️ Function exit: add_activation_to_rcfile" >&2
}

download_miniforge() {
  echo "↪️ Function entry: download_miniforge" >&2
  local installer_url="${_MINIFORGE_RELEASES_URL}/download/${MINIFORGE_VERSION}/${INSTALLER_FILENAME}"
  local checksum_url="${installer_url}.sha256"
  mkdir -p "$INSTALLER_DIR"
  echo "📥 Downloading installer from $installer_url" >&2
  net__fetch_url_file "$installer_url" "$INSTALLER"
  net__fetch_url_file "$checksum_url" "$CHECKSUM"
  echo "↩️ Function exit: download_miniforge" >&2
}

check_root_requirement() {
  echo "↪️ Function entry: check_root_requirement" >&2
  local _require
  case "$PREFIX" in
    /opt/* | /usr/* | /var/* | /srv/* | /snap/*) _require=true ;;
    *) _require=false ;;
  esac
  if [[ "$_require" == true ]]; then
    os__require_root
  else
    echo "ℹ️ Root not required for prefix '$PREFIX'. Skipping root check." >&2
  fi
  echo "↩️ Function exit: check_root_requirement" >&2
}

get_script_dir() {
  echo "↪️ Function entry: get_script_dir" >&2
  local script_dir
  script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
  echo "📤 Write output 'script_dir': '${script_dir}'" >&2
  echo "${script_dir}"
  echo "↩️ Function exit: get_script_dir" >&2
}

install_miniforge() {
  echo "↪️ Function entry: install_miniforge" >&2
  echo "📦 Installing Miniforge to $PREFIX"
  if [[ "$INTERACTIVE" == true ]]; then
    /bin/bash "$INSTALLER" -p "$PREFIX"
  else
    /bin/bash "$INSTALLER" -b -p "$PREFIX"
  fi
  echo "Displaying conda info:"
  "$CONDA_EXEC" info
  echo "Displaying conda config:"
  "$CONDA_EXEC" config --show
  echo "Displaying conda env list:"
  "$CONDA_EXEC" env list
  echo "Displaying conda list:"
  "$CONDA_EXEC" list --name base
  echo "↩️ Function exit: install_miniforge" >&2
}

set_executable_paths() {
  echo "↪️ Function entry: set_executable_paths" >&2
  __usage__() {
    echo "Usage:" >&2
    echo "  --verify (boolean): This is useful before running the post-installation steps
  (especially when the installation steps were skipped)
  to ensure that the executables are available.
  " >&2
    exit 0
  }
  local verify=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --verify)
        shift
        verify=true
        echo "📩 Read argument 'verify': '${verify}'" >&2
        ;;
      --help | -h) __usage__ ;;
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
  [ -z "${verify-}" ] && {
    echo "ℹ️ Argument 'verify' set to default value 'false'." >&2
    verify=false
  }
  CONDA_EXEC="${PREFIX}/bin/conda"
  MAMBA_EXEC="${PREFIX}/bin/mamba"
  if [[ "$verify" == false ]]; then
    return
  fi
  if [[ ! -f "$CONDA_EXEC" ]]; then
    if command -v conda > /dev/null 2>&1; then
      PREFIX="$(conda info --base)"
      CONDA_EXEC="${PREFIX}/bin/conda"
    else
      echo "⛔ Conda executable not found at '$CONDA_EXEC'." >&2
      exit 1
    fi
  fi
  if [[ ! -f "$MAMBA_EXEC" ]]; then
    if command -v mamba > /dev/null 2>&1; then
      MAMBA_EXEC="$(mamba info --base | tail -n 2 | head -n 1)/bin/mamba"
    else
      echo "⛔ Mamba executable not found at '$MAMBA_EXEC'." >&2
      exit 1
    fi
  fi
  if [[ ! -f "$CONDA_EXEC" ]]; then
    echo "⛔ Conda executable not found." >&2
    exit 1
  fi
  if [[ ! -f "$MAMBA_EXEC" ]]; then
    echo "⛔ Mamba executable not found." >&2
    exit 1
  fi
  echo "🎛 Conda executable located at '$CONDA_EXEC'."
  echo "🎛 Mamba executable located at '$MAMBA_EXEC'."
  echo "↩️ Function exit: set_executable_paths" >&2
}

set_installer_filename() {
  echo "↪️ Function entry: set_installer_filename" >&2
  local installer_platform
  installer_platform="$(os__kernel)-$(os__arch)"
  INSTALLER_FILENAME="Miniforge3-${MINIFORGE_VERSION}-${installer_platform}.sh"
  INSTALLER="${INSTALLER_DIR}/${INSTALLER_FILENAME}"
  CHECKSUM="${INSTALLER}.sha256"
  echo "↩️ Function exit: set_installer_filename" >&2
}

resolve_miniforge_version() {
  echo "↪️ Function entry: resolve_miniforge_version" >&2
  local tag conda_ver
  if [[ "$VERSION" == "latest" ]]; then
    echo "ℹ️ Resolving latest Miniforge release tag from GitHub API." >&2
    tag="$(github__latest_tag conda-forge/miniforge)" || {
      echo "⛔ Failed to resolve latest Miniforge version." >&2
      exit 1
    }
  else
    echo "ℹ️ Resolving Miniforge release tag for conda version '${VERSION}' from GitHub API." >&2
    local releases
    releases="$(github__release_tags conda-forge/miniforge)" || {
      echo "⛔ Failed to list Miniforge releases." >&2
      exit 1
    }
    [[ -z "$releases" ]] && {
      echo "⛔ Received empty release list from GitHub API." >&2
      exit 1
    }
    # Find tags matching <version>-<build_number>, pick the highest build number.
    tag="$(printf '%s\n' "$releases" |
      grep -E "^${VERSION}-[0-9]+$" |
      sort -t- -k2 -n | tail -1)"
    [[ -z "$tag" ]] && {
      echo "⛔ No Miniforge release found for conda version '${VERSION}'. Check available releases at ${_MINIFORGE_RELEASES_URL}" >&2
      exit 1
    }
  fi
  MINIFORGE_VERSION="$tag"
  # Extract conda version: the tag is "<version>-<build_number>"; strip the build suffix.
  conda_ver="${tag%-*}"
  RESOLVED_CONDA_VERSION="$conda_ver"
  echo "ℹ️ Resolved Miniforge tag: '${MINIFORGE_VERSION}' (conda version: '${RESOLVED_CONDA_VERSION}')." >&2
  echo "↩️ Function exit: resolve_miniforge_version" >&2
}

export_envs() {
  echo "↪️ Function entry: export_envs" >&2
  local tmpdir="$1"
  mkdir -p "$tmpdir"
  # Get non-base env paths: parse JSON array from 'conda env list --json'.
  # Filter to lines containing '"', extract the quoted value, then keep only
  # absolute paths (starts with '/') to skip the 'envs' key and other JSON tokens,
  # then exclude the base dir (PREFIX itself).
  local env_paths
  env_paths="$("$CONDA_EXEC" env list --json 2> /dev/null |
    grep '"' | sed 's/.*"\(.*\)".*/\1/' |
    grep '^/' |
    grep -v "^${PREFIX}/*$")" || true
  if [[ -z "$env_paths" ]]; then
    echo "ℹ️ No non-base environments found to preserve." >&2
    echo "↩️ Function exit: export_envs" >&2
    return
  fi
  while IFS= read -r env_path; do
    [[ -z "$env_path" ]] && continue
    local env_name
    env_name="$(basename "$env_path")"
    local yaml_path="${tmpdir}/${env_name}.yml"
    echo "📤 Exporting environment '${env_name}' to '${yaml_path}'." >&2
    if "$CONDA_EXEC" env export --from-history --name "$env_name" > "$yaml_path" 2> /dev/null; then
      echo "✅ Exported environment '${env_name}'." >&2
    else
      echo "⚠️ Failed to export environment '${env_name}'. Skipping." >&2
      rm -f "$yaml_path"
    fi
  done <<< "$env_paths"
  echo "↩️ Function exit: export_envs" >&2
}

recreate_envs() {
  echo "↪️ Function entry: recreate_envs" >&2
  local tmpdir="$1"
  if [[ ! -d "$tmpdir" ]]; then
    echo "ℹ️ No preserved environments directory found at '${tmpdir}'. Skipping." >&2
    echo "↩️ Function exit: recreate_envs" >&2
    return
  fi
  local found=false
  for yaml_path in "${tmpdir}"/*.yml; do
    [[ -f "$yaml_path" ]] || continue
    found=true
    local env_name
    env_name="$(basename "$yaml_path" .yml)"
    echo "📥 Recreating environment '${env_name}' from '${yaml_path}'." >&2
    if "$CONDA_EXEC" env create --file "$yaml_path"; then
      echo "✅ Recreated environment '${env_name}'." >&2
      rm -f "$yaml_path" # only delete on success; keep on failure for manual recovery
    else
      echo "⚠️ Failed to recreate environment '${env_name}'. YAML preserved at '${yaml_path}' for manual recovery." >&2
    fi
  done
  if [[ "$found" == false ]]; then
    echo "ℹ️ No preserved environment YAMLs found in '${tmpdir}'." >&2
  fi
  # Remove tmpdir only if empty (all YAMLs were successfully recreated and deleted above).
  # If any recreations failed, their YAMLs remain in tmpdir for manual recovery.
  [ -d "$tmpdir" ] && [ -z "$(ls -A "$tmpdir")" ] && rm -rf "$tmpdir"
  echo "↩️ Function exit: recreate_envs" >&2
}

uninstall_miniforge() {
  echo "↪️ Function entry: uninstall_miniforge" >&2
  echo "🗑 Uninstalling conda (Miniforge)." >&2
  if [[ "$PRESERVE_CONFIG" != "true" ]]; then
    "$CONDA_EXEC" init --reverse
  fi
  rm -rf "$("$CONDA_EXEC" info --base)"
  if [[ "$PRESERVE_CONFIG" != "true" ]]; then
    rm -f "$HOME/.condarc"
    rm -rf "$HOME/.conda"
    mapfile -t _uninstall_users < <(users__resolve_list)
    for _u in "${_uninstall_users[@]}"; do
      [[ -z "$_u" ]] && continue
      user_home=$(getent passwd "$_u" | cut -d: -f6)
      rm -rf "$user_home/.condarc"
      rm -rf "$user_home/.conda"
    done
  fi
  echo "↩️ Function exit: uninstall_miniforge" >&2
}

verify_miniforge() {
  echo "↪️ Function entry: verify_miniforge" >&2
  echo "📦 Verifying installer checksum" >&2
  checksum__verify_sha256_sidecar "$INSTALLER" "$CHECKSUM"
  echo "↩️ Function exit: verify_miniforge" >&2
}

export_path_main() {
  echo "↪️ Function entry: export_path_main" >&2
  if [ "$EXPORT_PATH" = "" ]; then
    echo "ℹ️ export_path is empty; skipping PATH export." >&2
    echo "↩️ Function exit: export_path_main" >&2
    return
  fi
  local _content="export PATH=\"${PREFIX}/bin:\${PATH}\""
  local _marker="conda PATH (install-miniforge)"
  local _target_files
  if [ "$EXPORT_PATH" != "auto" ]; then
    _target_files="$EXPORT_PATH"
  else
    local _is_public=true _is_root=false
    case "$PREFIX" in "${HOME}"/*) _is_public=false ;; esac
    [ "$(id -u)" = "0" ] && _is_root=true
    echo "ℹ️ Platform: '$(os__platform)'; is_public=${_is_public}; is_root=${_is_root}." >&2
    if [ "$_is_public" = true ] && [ "$_is_root" = true ]; then
      echo "ℹ️ Case A: system-wide PATH export (public install, root)." >&2
      _target_files="$(shell__system_path_files --profile_d "conda_bin_path.sh")"
    else
      echo "ℹ️ Case B: user-scoped PATH export." >&2
      # shellcheck disable=SC2119 # no args → uses $HOME default, intentional
      _target_files="$(shell__user_path_files)"
    fi
  fi
  shell__sync_block --files "$_target_files" --marker "$_marker" --content "$_content"
  echo "↩️ Function exit: export_path_main" >&2
  return
}

create_symlink() {
  echo "↪️ Function entry: create_symlink" >&2
  if [[ "$SYMLINK" != true ]]; then
    echo "ℹ️ symlink=false; skipping symlink creation." >&2
    echo "↩️ Function exit: create_symlink" >&2
    return 0
  fi
  shell__create_symlink \
    --src "$PREFIX" \
    --system-target "/opt/conda" \
    --user-target "${HOME}/miniforge3"
  echo "↩️ Function exit: create_symlink" >&2
  return 0
}

_cleanup_hook() {
  echo "↪️ Function entry: _cleanup_hook" >&2
  if [[ "${KEEP_INSTALLER-}" != "true" ]]; then
    [ -f "${INSTALLER-}" ] && {
      echo "🗑 Removing installer script at '$INSTALLER'" >&2
      rm -f "$INSTALLER"
    }
    [ -f "${CHECKSUM-}" ] && {
      echo "🗑 Removing checksum file at '$CHECKSUM'" >&2
      rm -f "$CHECKSUM"
    }
    [ -d "${INSTALLER_DIR-}" ] && [ -z "$(ls -A "$INSTALLER_DIR")" ] && {
      echo "🗑 Removing installation directory at '$INSTALLER_DIR'" >&2
      rmdir "$INSTALLER_DIR"
    }
  fi
  if [ -n "${PREFIX-}" ] && [ -d "$PREFIX" ]; then
    find "$PREFIX" -follow -type f -name '*.a' -delete 2> /dev/null || true
    find "$PREFIX" -follow -type f -name '*.pyc' -delete 2> /dev/null || true
  fi
  echo "↩️ Function exit: _cleanup_hook" >&2
}

readonly _CONDA_INIT_SCRIPT_RELPATH="etc/profile.d/conda.sh"
readonly _MAMBA_INIT_SCRIPT_RELPATH="etc/profile.d/mamba.sh"

# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
# shellcheck source=lib/github.sh
. "$_SELF_DIR/_lib/github.sh"
# shellcheck source=lib/checksum.sh
. "$_SELF_DIR/_lib/checksum.sh"

# ── Constants ────────────────────────────────────────────────────────────────
_MINIFORGE_RELEASES_URL="https://github.com/conda-forge/miniforge/releases"

check_root_requirement
set_executable_paths

resolve_miniforge_version
set_installer_filename
download_miniforge
if [[ -f "$CHECKSUM" ]]; then
  verify_miniforge
else
  echo "⚠️ Checksum file not found. Skipping verification." >&2
fi

if [[ -f "${PREFIX}/bin/conda" ]] || command -v conda > /dev/null 2>&1; then
  echo "⚠️ Conda installation found at '$PREFIX'." >&2
  # Version-match idempotency: if installed conda version already matches the
  # resolved version, skip silently regardless of if_exists.
  _installed_ver="$("${PREFIX}/bin/conda" --version 2> /dev/null | awk '{print $NF}')" || true
  if [[ -n "$_installed_ver" && "$_installed_ver" == "$RESOLVED_CONDA_VERSION" ]]; then
    echo "ℹ️ Installed conda version '${_installed_ver}' matches resolved version '${RESOLVED_CONDA_VERSION}'. Skipping install and continuing to post-install steps." >&2
  else
    case "$IF_EXISTS" in
      skip)
        echo "⏭️ if_exists=skip: existing conda detected; skipping install and continuing to post-install steps." >&2
        ;;
      fail)
        echo "⛔ if_exists=fail: conda already installed at '$PREFIX'. Remove it first or set if_exists=skip/reinstall." >&2
        exit 1
        ;;
      reinstall)
        echo "ℹ️ if_exists=reinstall: uninstalling existing conda, then installing fresh." >&2
        set_executable_paths --verify
        _env_preserve_dir="/tmp/conda-env-preserve"
        if [[ "$PRESERVE_ENVS" == "true" ]]; then
          export_envs "$_env_preserve_dir"
        fi
        uninstall_miniforge
        install_miniforge
        if [[ "$PRESERVE_ENVS" == "true" ]]; then
          set_executable_paths --verify
          recreate_envs "$_env_preserve_dir"
        fi
        ;;
      update)
        echo "ℹ️ if_exists=update: updating conda base environment to version '${RESOLVED_CONDA_VERSION}'." >&2
        set_executable_paths --verify
        "$CONDA_EXEC" install --name base --yes "conda=${RESOLVED_CONDA_VERSION}"
        ;;
      *)
        echo "⛔ Invalid value for 'if_exists': '$IF_EXISTS'. Use 'skip', 'fail', 'reinstall', or 'update'." >&2
        exit 1
        ;;
    esac
  fi
else
  install_miniforge
fi

set_executable_paths --verify

create_symlink
export_path_main

if [[ -n "${SHELL_ACTIVATIONS:-}" ]]; then add_activation_to_rcfile; fi
if [[ "$UPDATE_BASE" == true ]]; then
  echo "⚠️ Updating base conda environment."
  "$MAMBA_EXEC" update -n base --all -y
fi

if [[ -n "${WRITE_GROUP:-}" ]]; then
  export ADD_CURRENT_USER ADD_REMOTE_USER ADD_CONTAINER_USER ADD_USERS
  mapfile -t _write_users < <(users__resolve_list)
  users__set_write_permissions "$PREFIX" "$(id -nu)" "$WRITE_GROUP" "${_write_users[@]}"
fi
