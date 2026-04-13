#!/usr/bin/env bash
set -euo pipefail

__usage__() {
  echo "Usage:" >&2
  echo "  --rc_files (string): Paths to shell configuration files to append conda initialization to." >&2
  echo "  --activate_env (string): Name of a conda environment to activate.
  Only takes effect when rc_files is set.
  " >&2
  echo "  --bin_dir (string): Path to the conda installation directory.
  Corresponds to the BIN_DIR environment variable.
  " >&2
  echo "  --debug (boolean): Enable debug output." >&2
  echo "  --if_exists (string): What to do when conda is already installed at bin_dir.
  'skip'      — warn and continue to post-install steps (default).
  'fail'      — print an error and exit non-zero.
  'uninstall' — uninstall then install fresh.
  'update'    — update the base conda environment to the resolved version.
  " >&2
  echo "  --discard_envs: When if_exists is 'uninstall', do NOT export/recreate non-base conda
  environments across the reinstall. By default environments are preserved.
  NOTE: the devcontainer-feature.json option is 'preserve_envs' (boolean, default true);
  the CLI flag is inverted: --discard_envs sets preserve_envs=false.
  " >&2
  echo "  --discard_config: When if_exists is 'uninstall', run conda init --reverse and
  delete .condarc and .conda during uninstall. By default config is preserved.
  NOTE: the devcontainer-feature.json option is 'preserve_config' (boolean, default true);
  the CLI flag is inverted: --discard_config sets preserve_config=false.
  " >&2
  echo "  --group (string): Name of a user group to give access to conda.
  Only applies when set_permissions is true.
  " >&2
  echo "  --installer_dir (string): Directory to download the installer to.
  " >&2
  echo "  --interactive (boolean): Run the installer in interactive mode.
  The default is non-interactive.
  " >&2
  echo "  --keep_installer (boolean): Keep the Miniforge installer and checksum after installation." >&2
  echo "  --logfile (string): Log all output to this file in addition to console." >&2
  echo "  --version (string): Version of conda to install (e.g. '24.7.1').
  Defaults to 'latest'.
  " >&2
  echo "  --set_permissions (boolean): Set permissions for the conda installation directory.
  Adds users to the conda group and sets group-write bits.
  Only applies when set_permissions is true.
  " >&2
  echo "  --update_base (boolean): Update the base conda environment via conda update --all.
  Not recommended for production.
  " >&2
  echo "  --export_path (string): Controls which shell startup files receive the PATH export for \$BIN_DIR/bin.
  'auto' writes to all relevant system-wide files (public install + root)
  or user-scoped files (user install or non-root).
  '' (empty) skips all PATH writes.
  Newline-separated list of absolute paths: writes only to those files.
  " >&2
  echo "  --symlink (boolean): Create a symlink /opt/conda -> \$BIN_DIR when bin_dir is not /opt/conda.
  Ensures containerEnv PATH coverage works even with a custom bin_dir.
  No-op when bin_dir is already /opt/conda.
  Script default: false (devcontainer-feature.json default: true).
  " >&2
  echo "  --users (string): Comma-separated list of users to add to the conda group (e.g. 'alice,bob').
  Only applies when set_permissions is true.
  Defaults to the user running the script.
  " >&2
  exit 0
}

__cleanup__() {
  echo "↪️ Function entry: __cleanup__" >&2
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
  if [ -n "${BIN_DIR-}" ] && [ -d "$BIN_DIR" ]; then
    find "$BIN_DIR" -follow -type f -name '*.a' -delete 2> /dev/null || true
    find "$BIN_DIR" -follow -type f -name '*.pyc' -delete 2> /dev/null || true
  fi
  logging__cleanup
  echo "↩️ Function exit: __cleanup__" >&2
}

add_activation_to_rcfile() {
  echo "↪️ Function entry: add_activation_to_rcfile" >&2
  local conda_script="$BIN_DIR/$_CONDA_INIT_SCRIPT_RELPATH"
  local mamba_script="$BIN_DIR/$_MAMBA_INIT_SCRIPT_RELPATH"
  lines=(
    ". '$conda_script'"
    ". '$mamba_script'"
  )
  if [[ -n "$ACTIVATE_ENV" ]]; then
    lines+=("conda activate $ACTIVATE_ENV")
  fi
  for path in "${RC_FILES[@]}"; do
    [[ -z "$path" ]] && continue
    echo "▶️ Sourcing activation script to '$path'"
    [[ -f "$path" ]] || touch "$path"
    for line in "${lines[@]}"; do
      if grep -Fxq "$line" "$path"; then
        echo "⏭️ Line already exists in '$path': $line"
      else
        echo "$line" >> "$path"
        echo "ℹ️ Appended to '$path': $line"
      fi
    done
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
  case "$BIN_DIR" in
    /opt/* | /usr/* | /var/* | /srv/* | /snap/*) _require=true ;;
    *) _require=false ;;
  esac
  if [[ "$_require" == true ]]; then
    os__require_root
  else
    echo "ℹ️ Root not required for bin_dir '$BIN_DIR'. Skipping root check." >&2
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
  echo "📦 Installing Miniforge to $BIN_DIR"
  if [[ "$INTERACTIVE" == true ]]; then
    /bin/bash "$INSTALLER" -p "$BIN_DIR"
  else
    /bin/bash "$INSTALLER" -b -p "$BIN_DIR"
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
  CONDA_EXEC="${BIN_DIR}/bin/conda"
  MAMBA_EXEC="${BIN_DIR}/bin/mamba"
  if [[ "$verify" == false ]]; then
    return
  fi
  if [[ ! -f "$CONDA_EXEC" ]]; then
    if command -v conda > /dev/null 2>&1; then
      BIN_DIR="$(conda info --base)"
      CONDA_EXEC="${BIN_DIR}/bin/conda"
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

set_permissions() {
  echo "↪️ Function entry: set_permissions" >&2
  echo "🔐 Setting permissions for conda directory."
  getent group "$GROUP" > /dev/null || groupadd -r "$GROUP"
  for _u in "${_USERS_ARR[@]}"; do
    [[ -z "$_u" ]] && continue
    id -nG "$_u" | grep -qw "$GROUP" || usermod -a -G "$GROUP" "$_u"
  done
  chown -R "${_USERS_ARR[0]}:$GROUP" "$BIN_DIR"
  chmod -R g+r+w "$BIN_DIR"
  find "$BIN_DIR" -type d -print0 | xargs -n 1 -0 chmod g+s
  echo "↩️ Function exit: set_permissions" >&2
}

export_envs() {
  echo "↪️ Function entry: export_envs" >&2
  local tmpdir="$1"
  mkdir -p "$tmpdir"
  # Get non-base env paths: parse JSON array from 'conda env list --json'.
  # Filter to lines containing '"', extract the quoted value, then keep only
  # absolute paths (starts with '/') to skip the 'envs' key and other JSON tokens,
  # then exclude the base dir (BIN_DIR itself).
  local env_paths
  env_paths="$("$CONDA_EXEC" env list --json 2> /dev/null |
    grep '"' | sed 's/.*"\(.*\)".*/\1/' |
    grep '^/' |
    grep -v "^${BIN_DIR}/*$")" || true
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
    for _u in "${_USERS_ARR[@]}"; do
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
  local _content="export PATH=\"${BIN_DIR}/bin:\${PATH}\""
  local _marker="conda PATH (install-miniforge)"
  local _target_files
  if [ "$EXPORT_PATH" != "auto" ]; then
    _target_files="$EXPORT_PATH"
  else
    local _is_public=true _is_root=false
    case "$BIN_DIR" in "${HOME}"/*) _is_public=false ;; esac
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
    return
  fi
  if [ "$BIN_DIR" = "/opt/conda" ]; then
    echo "ℹ️ bin_dir is already /opt/conda; no symlink needed." >&2
    echo "↩️ Function exit: create_symlink" >&2
    return
  fi
  if [ -d "/opt/conda" ] && [ ! -L "/opt/conda" ]; then
    echo "⛔ /opt/conda exists as a real directory; cannot create symlink. Disable symlink or remove the directory." >&2
    exit 1
  fi
  [ -L "/opt/conda" ] && rm -f "/opt/conda"
  ln -s "$BIN_DIR" /opt/conda
  echo "✅ Created symlink /opt/conda -> $BIN_DIR." >&2
  echo "↩️ Function exit: create_symlink" >&2
}

readonly _CONDA_INIT_SCRIPT_RELPATH="etc/profile.d/conda.sh"
readonly _MAMBA_INIT_SCRIPT_RELPATH="etc/profile.d/mamba.sh"

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
# shellcheck source=lib/github.sh
. "$_SELF_DIR/_lib/github.sh"
# shellcheck source=lib/checksum.sh
. "$_SELF_DIR/_lib/checksum.sh"
logging__setup
echo "↪️ Script entry: Miniforge Installation Devcontainer Feature Installer" >&2
trap '__cleanup__' EXIT

# ── Constants ────────────────────────────────────────────────────────────────
_MINIFORGE_RELEASES_URL="https://github.com/conda-forge/miniforge/releases"

ospkg__run --manifest "${_SELF_DIR}/../dependencies/base.yaml" --check_installed

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  RC_FILES=()
  ACTIVATE_ENV=""
  BIN_DIR=""
  DEBUG=""
  IF_EXISTS=""
  GROUP=""
  INSTALLER_DIR=""
  INTERACTIVE=""
  LOGFILE=""
  VERSION=""
  KEEP_INSTALLER=""
  SET_PERMISSIONS=""
  UPDATE_BASE=""
  USERS=""
  PRESERVE_ENVS=""
  PRESERVE_CONFIG=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --rc_files)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          RC_FILES+=("$1")
          echo "📩 Read argument 'rc_files': '${1}'" >&2
          shift
        done
        ;;
      --activate_env)
        shift
        ACTIVATE_ENV="$1"
        echo "📩 Read argument 'activate_env': '${ACTIVATE_ENV}'" >&2
        shift
        ;;
      --bin_dir)
        shift
        BIN_DIR="$1"
        echo "📩 Read argument 'bin_dir': '${BIN_DIR}'" >&2
        shift
        ;;
      --debug)
        shift
        DEBUG=true
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        ;;
      --if_exists)
        shift
        IF_EXISTS="$1"
        echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
        shift
        ;;
      --group)
        shift
        GROUP="$1"
        echo "📩 Read argument 'group': '${GROUP}'" >&2
        shift
        ;;
      --install)
        shift
        echo "⚠️ --install is deprecated; use --if_exists. Ignored." >&2
        ;;
      --installer_dir)
        shift
        INSTALLER_DIR="$1"
        echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
        shift
        ;;
      --interactive)
        shift
        INTERACTIVE=true
        echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
        ;;
      --keep_installer)
        shift
        KEEP_INSTALLER=true
        echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      --version)
        shift
        VERSION="$1"
        echo "📩 Read argument 'version': '${VERSION}'" >&2
        shift
        ;;
      --set_permissions)
        shift
        SET_PERMISSIONS=true
        echo "📩 Read argument 'set_permissions': '${SET_PERMISSIONS}'" >&2
        ;;
      --update_base)
        shift
        UPDATE_BASE=true
        echo "📩 Read argument 'update_base': '${UPDATE_BASE}'" >&2
        ;;
      --export_path)
        shift
        EXPORT_PATH="$1"
        echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
        shift
        ;;
      --symlink)
        shift
        SYMLINK=true
        echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
        ;;
      --users)
        shift
        USERS="$1"
        echo "📩 Read argument 'users': '${USERS}'" >&2
        shift
        ;;
      --discard_envs)
        shift
        PRESERVE_ENVS=false
        echo "📩 Read argument 'discard_envs': true" >&2
        ;;
      --discard_config)
        shift
        PRESERVE_CONFIG=false
        echo "📩 Read argument 'discard_config': true" >&2
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
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  if [ "${RC_FILES+defined}" ]; then
    if [ -n "${RC_FILES-}" ]; then
      echo "ℹ️ Parse 'rc_files' into array: '${RC_FILES}'" >&2
    fi
    mapfile -t _tmp_array < <(printf '%s' "${RC_FILES-}" | sed 's/ :: /\n/g')
    RC_FILES=("${_tmp_array[@]}")
    for _item in "${RC_FILES[@]}"; do
      echo "📩 Read argument 'rc_files': '${_item}'" >&2
    done
    unset _item
    unset _tmp_array
  fi
  [ "${ACTIVATE_ENV+defined}" ] && echo "📩 Read argument 'activate_env': '${ACTIVATE_ENV}'" >&2
  [ "${BIN_DIR+defined}" ] && echo "📩 Read argument 'bin_dir': '${BIN_DIR}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${DOWNLOAD+defined}" ] && echo "📩 Read argument 'download (deprecated)': '${DOWNLOAD}'" >&2
  [ "${IF_EXISTS+defined}" ] && echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
  [ "${GROUP+defined}" ] && echo "📩 Read argument 'group': '${GROUP}'" >&2
  [ "${INSTALL+defined}" ] && echo "⚠️ 'INSTALL' env var is deprecated; use IF_EXISTS." >&2
  [ "${INSTALLER_DIR+defined}" ] && echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
  [ "${INTERACTIVE+defined}" ] && echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
  [ "${KEEP_INSTALLER+defined}" ] && echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${VERSION+defined}" ] && echo "📩 Read argument 'version': '${VERSION}'" >&2
  [ "${REINSTALL+defined}" ] && echo "⚠️ 'REINSTALL' env var is deprecated; use IF_EXISTS=uninstall." >&2
  [ "${SET_PERMISSIONS+defined}" ] && echo "📩 Read argument 'set_permissions': '${SET_PERMISSIONS}'" >&2
  [ "${UPDATE_BASE+defined}" ] && echo "📩 Read argument 'update_base': '${UPDATE_BASE}'" >&2
  [ "${EXPORT_PATH+defined}" ] && echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
  [ "${SYMLINK+defined}" ] && echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
  [ "${USERS+defined}" ] && echo "📩 Read argument 'users': '${USERS}'" >&2
  [ "${PRESERVE_ENVS+defined}" ] && echo "📩 Read argument 'preserve_envs': '${PRESERVE_ENVS}'" >&2
  [ "${PRESERVE_CONFIG+defined}" ] && echo "📩 Read argument 'preserve_config': '${PRESERVE_CONFIG}'" >&2
fi
[[ "${DEBUG:-}" == true ]] && set -x
{ [ "${RC_FILES+isset}" != "isset" ] || [ ${#RC_FILES[@]} -eq 0 ]; } && {
  echo "ℹ️ Argument 'RC_FILES' set to default value '()'." >&2
  RC_FILES=()
}
[ -z "${ACTIVATE_ENV-}" ] && {
  echo "ℹ️ Argument 'ACTIVATE_ENV' set to default value 'base'." >&2
  ACTIVATE_ENV="base"
}
[ -z "${BIN_DIR-}" ] && {
  echo "ℹ️ Argument 'BIN_DIR' set to default value '/opt/conda'." >&2
  BIN_DIR="/opt/conda"
}
[ -z "${DEBUG-}" ] && {
  echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2
  DEBUG=false
}
[ -z "${IF_EXISTS-}" ] && {
  echo "ℹ️ Argument 'IF_EXISTS' set to default value 'skip'." >&2
  IF_EXISTS="skip"
}
[ -z "${GROUP-}" ] && {
  echo "ℹ️ Argument 'GROUP' set to default value 'conda'." >&2
  GROUP="conda"
}
[ -z "${INSTALLER_DIR-}" ] && {
  echo "ℹ️ Argument 'INSTALLER_DIR' set to default value '/tmp/miniforge-installer'." >&2
  INSTALLER_DIR="/tmp/miniforge-installer"
}
[ -z "${INTERACTIVE-}" ] && {
  echo "ℹ️ Argument 'INTERACTIVE' set to default value 'false'." >&2
  INTERACTIVE=false
}
[ -z "${KEEP_INSTALLER-}" ] && {
  echo "ℹ️ Argument 'KEEP_INSTALLER' set to default value 'false'." >&2
  KEEP_INSTALLER=false
}
[ -z "${LOGFILE-}" ] && {
  echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2
  LOGFILE=""
}
[ -z "${VERSION-}" ] && {
  echo "ℹ️ Argument 'VERSION' set to default value 'latest'." >&2
  VERSION="latest"
}
[ -z "${SET_PERMISSIONS-}" ] && {
  echo "ℹ️ Argument 'SET_PERMISSIONS' set to default value 'false'." >&2
  SET_PERMISSIONS=false
}
[ -z "${UPDATE_BASE-}" ] && {
  echo "ℹ️ Argument 'UPDATE_BASE' set to default value 'false'." >&2
  UPDATE_BASE=false
}
[ -z "${EXPORT_PATH+x}" ] && {
  echo "ℹ️ Argument 'EXPORT_PATH' set to default value 'auto'." >&2
  EXPORT_PATH="auto"
}
[ -z "${SYMLINK+x}" ] && {
  echo "ℹ️ Argument 'SYMLINK' set to default value 'false'." >&2
  SYMLINK=false
}
[ -z "${USERS-}" ] && {
  echo "ℹ️ Argument 'USERS' set to default value '$(id -nu)'." >&2
  USERS="$(id -nu)"
}
IFS=',' read -ra _USERS_ARR <<< "$USERS"
[ -z "${PRESERVE_ENVS-}" ] && {
  echo "ℹ️ Argument 'PRESERVE_ENVS' set to default value 'true'." >&2
  PRESERVE_ENVS="true"
}
[ -z "${PRESERVE_CONFIG-}" ] && {
  echo "ℹ️ Argument 'PRESERVE_CONFIG' set to default value 'true'." >&2
  PRESERVE_CONFIG="true"
}

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

if [[ -f "${BIN_DIR}/bin/conda" ]] || command -v conda > /dev/null 2>&1; then
  echo "⚠️ Conda installation found at '$BIN_DIR'." >&2
  # Version-match idempotency: if installed conda version already matches the
  # resolved version, skip silently regardless of if_exists.
  _installed_ver="$("${BIN_DIR}/bin/conda" --version 2> /dev/null | awk '{print $NF}')" || true
  if [[ -n "$_installed_ver" && "$_installed_ver" == "$RESOLVED_CONDA_VERSION" ]]; then
    echo "ℹ️ Installed conda version '${_installed_ver}' matches resolved version '${RESOLVED_CONDA_VERSION}'. Skipping install and continuing to post-install steps." >&2
  else
    case "$IF_EXISTS" in
      skip)
        echo "⏭️ if_exists=skip: existing conda detected; skipping install and continuing to post-install steps." >&2
        ;;
      fail)
        echo "⛔ if_exists=fail: conda already installed at '$BIN_DIR'. Remove it first or set if_exists=skip/uninstall." >&2
        exit 1
        ;;
      uninstall)
        echo "ℹ️ if_exists=uninstall: uninstalling existing conda, then installing fresh." >&2
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
        echo "⛔ Invalid value for 'if_exists': '$IF_EXISTS'. Use 'skip', 'fail', 'uninstall', or 'update'." >&2
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

if [[ ${#RC_FILES[@]} -gt 0 ]]; then add_activation_to_rcfile; fi
if [[ "$UPDATE_BASE" == true ]]; then
  echo "⚠️ Updating base conda environment."
  "$MAMBA_EXEC" update -n base --all -y
fi

if [[ "$SET_PERMISSIONS" == true ]]; then set_permissions; fi

echo "✅ Conda installation complete."
echo "↩️ Script exit: Miniforge Installation Devcontainer Feature Installer" >&2
