#!/usr/bin/env bash
set -euo pipefail

__usage__() {
  echo "Usage:" >&2
  echo "  --rc_files (string): Paths to shell configuration files to append conda initialization to." >&2
  echo "  --activate_env (string): Name of a conda environment to activate.
  Only takes effect when rc_files is set.
  " >&2
  echo "  --conda_dir (string): Path to the conda installation directory.
  Corresponds to the CONDA_DIR environment variable.
  " >&2
  echo "  --debug (boolean): Enable debug output." >&2
  echo "  --if_exists (string): What to do when conda is already installed at conda_dir.
  'skip'      — warn and continue to post-install steps (default).
  'fail'      — print an error and exit non-zero.
  'uninstall' — uninstall then install fresh.
  'update'    — reserved; not yet implemented.
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
  echo "  --conda_version (string): Version of conda to install (e.g. '24.7.1').
  Defaults to 'latest'.
  " >&2
  echo "  --set_permissions (boolean): Set permissions for the conda installation directory.
  Adds users to the conda group and sets group-write bits.
  Only applies when set_permissions is true.
  " >&2
  echo "  --update_base (boolean): Update the base conda environment via conda update --all.
  Not recommended for production.
  " >&2
  echo "  --export_path (string): Controls which shell startup files receive the PATH export for \$CONDA_DIR/bin.
  'auto' writes to all relevant system-wide files (public install + root)
  or user-scoped files (user install or non-root).
  '' (empty) skips all PATH writes.
  Newline-separated list of absolute paths: writes only to those files.
  " >&2
  echo "  --symlink (boolean): Create a symlink /opt/conda -> \$CONDA_DIR when conda_dir is not /opt/conda.
  Ensures containerEnv PATH coverage works even with a custom conda_dir.
  No-op when conda_dir is already /opt/conda.
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
  if [[ "${KEEP_INSTALLER-}" == false ]]; then
      [ -f "${INSTALLER-}" ] && { echo "🗑 Removing installer script at '$INSTALLER'" >&2; rm -f "$INSTALLER"; }
      [ -f "${CHECKSUM-}" ] && { echo "🗑 Removing checksum file at '$CHECKSUM'" >&2; rm -f "$CHECKSUM"; }
      [ -d "${INSTALLER_DIR-}" ] && [ -z "$(ls -A "$INSTALLER_DIR")" ] && {
          echo "🗑 Removing installation directory at '$INSTALLER_DIR'" >&2
          rmdir "$INSTALLER_DIR"
      }
  fi
  if [ -n "${CONDA_DIR-}" ] && [ -d "$CONDA_DIR" ]; then
      find "$CONDA_DIR" -follow -type f -name '*.a' -delete 2>/dev/null || true
      find "$CONDA_DIR" -follow -type f -name '*.pyc' -delete 2>/dev/null || true
  fi
  if [ -n "${LOGFILE-}" ]; then
    exec 1>&3 2>&4
    wait 2>/dev/null
    echo "ℹ️ Write logs to file '$LOGFILE'" >&2
    mkdir -p "$(dirname "$LOGFILE")"
    cat "$_LOGFILE_TMP" >> "$LOGFILE"
    rm -f "$_LOGFILE_TMP"
  fi
  echo "↩️ Function exit: __cleanup__" >&2
}

add_activation_to_rcfile() {
  echo "↪️ Function entry: add_activation_to_rcfile" >&2
  local conda_script="$CONDA_DIR/$_CONDA_INIT_SCRIPT_RELPATH"
  local mamba_script="$CONDA_DIR/$_MAMBA_INIT_SCRIPT_RELPATH"
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
  local installer_url
  local checksum_url
  if [[ "$CONDA_VERSION" == "latest" ]]; then
      # The rolling /latest/download/ URL has no version in the filename, but the
      # checksum asset on the same release IS named with the version tag.
      local versioned_filename="Miniforge3-${MINIFORGE_VERSION}-${INSTALLER_FILENAME#Miniforge3-}"
      installer_url="https://github.com/conda-forge/miniforge/releases/latest/download/${INSTALLER_FILENAME}"
      checksum_url="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${versioned_filename}.sha256"
  else
      installer_url="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${INSTALLER_FILENAME}"
      checksum_url="${installer_url}.sha256"
  fi
  mkdir -p "$INSTALLER_DIR"
  echo "📥 Downloading installer from $installer_url" >&2
  curl --fail --location --retry 3 --output "$INSTALLER" "$installer_url"
  curl --fail --location --retry 3 --output "$CHECKSUM" "$checksum_url"
  echo "↩️ Function exit: download_miniforge" >&2
}

exit_if_not_root() {
  echo "↪️ Function entry: exit_if_not_root" >&2
  if [ "$(id -u)" -ne 0 ]; then
      echo '⛔ This script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.' >&2
      exit 1
  fi
  echo "↩️ Function exit: exit_if_not_root" >&2
}

check_root_requirement() {
  echo "↪️ Function entry: check_root_requirement" >&2
  local _require
  case "$CONDA_DIR" in
    /opt/*|/usr/*|/var/*|/srv/*|/snap/*) _require=true ;;
    *) _require=false ;;
  esac
  if [[ "$_require" == true ]]; then
      exit_if_not_root
  else
      echo "ℹ️ Root not required for conda_dir '$CONDA_DIR'. Skipping root check." >&2
  fi
  echo "↩️ Function exit: check_root_requirement" >&2
}

get_script_dir() {
  echo "↪️ Function entry: get_script_dir" >&2
  local script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
  echo "📤 Write output 'script_dir': '${script_dir}'" >&2
  echo "${script_dir}"
  echo "↩️ Function exit: get_script_dir" >&2
}

install_miniforge() {
  echo "↪️ Function entry: install_miniforge" >&2
  echo "📦 Installing Miniforge to $CONDA_DIR"
  if [[ "$INTERACTIVE" == true ]]; then
      /bin/bash "$INSTALLER" -p "$CONDA_DIR"
  else
      /bin/bash "$INSTALLER" -b -p "$CONDA_DIR"
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
      --verify) shift; verify=true; echo "📩 Read argument 'verify': '${verify}'" >&2;;
      --help|-h) __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
  [ -z "${verify-}" ] && { echo "ℹ️ Argument 'verify' set to default value 'false'." >&2; verify=false; }
  CONDA_EXEC="${CONDA_DIR}/bin/conda"
  MAMBA_EXEC="${CONDA_DIR}/bin/mamba"
  if [[ "$verify" == false ]]; then
      return
  fi
  if [[ ! -f "$CONDA_EXEC" ]]; then
      if command -v conda >/dev/null 2>&1; then
          CONDA_DIR="$(conda info --base)"
          CONDA_EXEC="${CONDA_DIR}/bin/conda"
      else
          echo "⛔ Conda executable not found at '$CONDA_EXEC'." >&2
          exit 1
      fi
  fi
  if [[ ! -f "$MAMBA_EXEC" ]]; then
      if command -v mamba >/dev/null 2>&1; then
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
  local installer_platform="$(uname)-$(uname -m)"
  if [[ "$CONDA_VERSION" == "latest" ]]; then
      INSTALLER_FILENAME="Miniforge3-${installer_platform}.sh"
  else
      INSTALLER_FILENAME="Miniforge3-${MINIFORGE_VERSION}-${installer_platform}.sh"
  fi
  INSTALLER="${INSTALLER_DIR}/${INSTALLER_FILENAME}"
  CHECKSUM="${INSTALLER}.sha256"
  echo "↩️ Function exit: set_installer_filename" >&2
}

resolve_miniforge_version() {
  echo "↪️ Function entry: resolve_miniforge_version" >&2
  local api_base="https://api.github.com/repos/conda-forge/miniforge/releases"
  local tag conda_ver
  if [[ "$CONDA_VERSION" == "latest" ]]; then
    echo "ℹ️ Resolving latest Miniforge release tag from GitHub API." >&2
    tag="$(curl --fail --silent --location \
               --header "Accept: application/vnd.github+json" \
               "${api_base}/latest" \
           | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')" || {
      echo "⛔ Failed to reach GitHub API to resolve latest Miniforge version." >&2
      exit 1
    }
    [[ -z "$tag" ]] && { echo "⛔ Could not parse tag_name from GitHub API response." >&2; exit 1; }
  else
    echo "ℹ️ Resolving Miniforge release tag for conda version '${CONDA_VERSION}' from GitHub API." >&2
    local releases
    releases="$(curl --fail --silent --location \
                     --header "Accept: application/vnd.github+json" \
                     "${api_base}?per_page=100" \
                 | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')" || {
      echo "⛔ Failed to reach GitHub API to list Miniforge releases." >&2
      exit 1
    }
    [[ -z "$releases" ]] && { echo "⛔ Received empty release list from GitHub API." >&2; exit 1; }
    # Find tags matching <version>-<build_number>, pick the highest build number.
    tag="$(printf '%s\n' "$releases" \
           | grep -E "^${CONDA_VERSION}-[0-9]+$" \
           | sort -t- -k2 -n | tail -1)"
    [[ -z "$tag" ]] && {
      echo "⛔ No Miniforge release found for conda version '${CONDA_VERSION}'. Check available releases at https://github.com/conda-forge/miniforge/releases" >&2
      exit 1
    }
  fi
  MINIFORGE_VERSION="$tag"
  # Extract conda version: the tag is "<conda_version>-<build_number>"; strip the build suffix.
  conda_ver="${tag%-*}"
  RESOLVED_CONDA_VERSION="$conda_ver"
  echo "ℹ️ Resolved Miniforge tag: '${MINIFORGE_VERSION}' (conda version: '${RESOLVED_CONDA_VERSION}')." >&2
  echo "↩️ Function exit: resolve_miniforge_version" >&2
}

set_permissions() {
  echo "↪️ Function entry: set_permissions" >&2
  echo "🔐 Setting permissions for conda directory."
  getent group "$GROUP" >/dev/null || groupadd -r "$GROUP"
  for _u in "${_USERS_ARR[@]}"; do
      [[ -z "$_u" ]] && continue
      id -nG "$_u" | grep -qw "$GROUP" || usermod -a -G "$GROUP" "$_u"
  done
  chown -R "${_USERS_ARR[0]}:$GROUP" "$CONDA_DIR"
  chmod -R g+r+w "$CONDA_DIR"
  find "$CONDA_DIR" -type d -print0 | xargs -n 1 -0 chmod g+s
  echo "↩️ Function exit: set_permissions" >&2
}

uninstall_miniforge() {
  echo "↪️ Function entry: uninstall_miniforge" >&2
  echo "🗑 Uninstalling conda (Miniforge)."
  "$CONDA_EXEC" init --reverse
  rm -rf "$("$CONDA_EXEC" info --base)"
  rm -f "$HOME/.condarc"
  rm -rf "$HOME/.conda"
  for _u in "${_USERS_ARR[@]}"; do
      [[ -z "$_u" ]] && continue
      user_home=$(getent passwd "$_u" | cut -d: -f6)
      rm -rf "$user_home/.condarc"
      rm -rf "$user_home/.conda"
  done
  echo "↩️ Function exit: uninstall_miniforge" >&2
}

verify_miniforge() {
  echo "↪️ Function entry: verify_miniforge" >&2
  echo "📦 Verifying installer checksum"
  if command -v sha256sum >/dev/null 2>&1; then
      if (cd "$INSTALLER_DIR" && sha256sum --check --status "$CHECKSUM"); then
          echo "✅ Checksum verification passed" >&2
      else
          echo "❌ Checksum verification failed" >&2
          exit 1
      fi
  elif command -v shasum >/dev/null 2>&1; then
      if (cd "$INSTALLER_DIR" && shasum --algorithm 256 --check --status "$CHECKSUM"); then
          echo "✅ Checksum verification passed" >&2
      else
          echo "❌ Checksum verification failed" >&2
          exit 1
      fi
  else
      echo "⛔ Neither sha256sum nor shasum is available." >&2
      exit 1
  fi
  echo "↩️ Function exit: verify_miniforge" >&2
}


detect_platform() {
  echo "↪️ Function entry: detect_platform" >&2
  local id="" id_like=""
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi
  case "$id" in
    debian|ubuntu)                            echo "debian"; echo "↩️ Function exit: detect_platform" >&2; return ;;
    alpine)                                   echo "alpine"; echo "↩️ Function exit: detect_platform" >&2; return ;;
    rhel|centos|fedora|rocky|almalinux)       echo "rhel";   echo "↩️ Function exit: detect_platform" >&2; return ;;
  esac
  case "$id_like" in
    *debian*|*ubuntu*)                        echo "debian"; echo "↩️ Function exit: detect_platform" >&2; return ;;
    *alpine*)                                 echo "alpine"; echo "↩️ Function exit: detect_platform" >&2; return ;;
    *rhel*|*fedora*|*centos*|*"Red Hat"*)     echo "rhel";   echo "↩️ Function exit: detect_platform" >&2; return ;;
  esac
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "macos"; echo "↩️ Function exit: detect_platform" >&2; return
  fi
  echo "debian"  # fallback
  echo "↩️ Function exit: detect_platform" >&2
}

_platform_bashrc() {
  local platform="$1"
  case "$platform" in
    alpine)      echo "/etc/bash/bashrc" ;;
    rhel|macos)  echo "/etc/bashrc" ;;
    *)           echo "/etc/bash.bashrc" ;;
  esac
}

_platform_zshenv() {
  local platform="$1"
  case "$platform" in
    rhel|macos)  echo "/etc/zshenv" ;;
    *)           echo "/etc/zsh/zshenv" ;;
  esac
}

_detect_bashenv_target() {
  echo "↪️ Function entry: _detect_bashenv_target" >&2
  local platform="$1"
  # 1. Live environment variable
  if [ -n "${BASH_ENV:-}" ]; then
    echo "ℹ️ BASH_ENV already set to '${BASH_ENV}'; reusing." >&2
    echo "$BASH_ENV"
    echo "↩️ Function exit: _detect_bashenv_target" >&2
    return
  fi
  # 2. Existing /etc/environment entry
  if [ -f /etc/environment ]; then
    local env_val
    env_val="$(grep -m1 '^BASH_ENV=' /etc/environment 2>/dev/null || true)"
    if [ -n "$env_val" ]; then
      env_val="${env_val#BASH_ENV=}"
      env_val="${env_val#[\"\']}"
      env_val="${env_val%[\"\']}"
      echo "ℹ️ Found BASH_ENV='${env_val}' in /etc/environment; reusing." >&2
      echo "$env_val"
      echo "↩️ Function exit: _detect_bashenv_target" >&2
      return
    fi
  fi
  # 3. Create new bashenv file and register in /etc/environment
  local canonical_bashrc
  canonical_bashrc="$(_platform_bashrc "$platform")"
  local bashenv_dir
  bashenv_dir="$(dirname "$canonical_bashrc")"
  local bashenv_path="${bashenv_dir}/bashenv"
  echo "ℹ️ No BASH_ENV found; creating '${bashenv_path}' and registering in /etc/environment." >&2
  mkdir -p "$bashenv_dir"
  [ -f "$bashenv_path" ] || touch "$bashenv_path"
  printf 'BASH_ENV="%s"\n' "$bashenv_path" >> /etc/environment
  echo "$bashenv_path"
  echo "↩️ Function exit: _detect_bashenv_target" >&2
}

build_export_path_list() {
  echo "↪️ Function entry: build_export_path_list" >&2
  if [ "$EXPORT_PATH" = "" ]; then
    echo "↩️ Function exit: build_export_path_list" >&2
    return
  fi
  if [ "$EXPORT_PATH" != "auto" ]; then
    echo "$EXPORT_PATH"
    echo "↩️ Function exit: build_export_path_list" >&2
    return
  fi
  # auto mode: determine Case A (public + root) vs Case B (user/non-root)
  local is_public=true
  local is_root=false
  case "$CONDA_DIR" in
    "${HOME}"/*) is_public=false ;;
  esac
  [ "$(id -u)" = "0" ] && is_root=true
  local platform
  platform="$(detect_platform)"
  echo "📤 Write output 'platform': '${platform}'" >&2
  if [ "$is_public" = true ] && [ "$is_root" = true ]; then
    echo "ℹ️ Case A: system-wide PATH export (public install, root)." >&2
    # 1. BASH_ENV target (non-login non-interactive bash)
    local bashenv_target
    bashenv_target="$(_detect_bashenv_target "$platform")"
    echo "$bashenv_target"
    # 2. /etc/profile.d/conda_bin_path.sh (login shells)
    echo "/etc/profile.d/conda_bin_path.sh"
    # 3. Global bashrc (non-login interactive bash)
    local bashrc=""
    for f in /etc/bash.bashrc /etc/bashrc /etc/bash/bashrc; do
      [ -f "$f" ] && { bashrc="$f"; break; }
    done
    [ -z "$bashrc" ] && bashrc="$(_platform_bashrc "$platform")"
    echo "$bashrc"
    # 4. Global zshenv (all Zsh invocations)
    local zshenv=""
    for f in /etc/zsh/zshenv /etc/zshenv; do
      [ -f "$f" ] && { zshenv="$f"; break; }
    done
    [ -z "$zshenv" ] && zshenv="$(_platform_zshenv "$platform")"
    echo "$zshenv"
  else
    echo "ℹ️ Case B: user-scoped PATH export." >&2
    # 1. ~/.bashrc (non-login interactive bash)
    echo "${HOME}/.bashrc"
    # 2. Login file
    local login_file=""
    for f in "${HOME}/.bash_profile" "${HOME}/.bash_login" "${HOME}/.profile"; do
      [ -f "$f" ] && { login_file="$f"; break; }
    done
    [ -z "$login_file" ] && login_file="${HOME}/.bash_profile"
    echo "$login_file"
    # 3. Zsh env file
    local zdotdir="${ZDOTDIR:-$HOME}"
    echo "${zdotdir}/.zshenv"
  fi
  echo "↩️ Function exit: build_export_path_list" >&2
}

write_path_block() {
  echo "↪️ Function entry: write_path_block" >&2
  local target_file="$1"
  local begin_marker="# >>> conda PATH (install-miniforge) >>>"
  local end_marker="# <<< conda PATH (install-miniforge) <<<"
  local block_content="export PATH=\"${CONDA_DIR}/bin:\${PATH}\""
  mkdir -p "$(dirname "$target_file")"
  [ -f "$target_file" ] || touch "$target_file"
  if grep -qF "$begin_marker" "$target_file"; then
    awk -v begin="$begin_marker" -v end="$end_marker" -v content="$block_content" '
      $0 == begin { print; print content; found=1; next }
      found && $0 == end { print; found=0; next }
      found { next }
      { print }
    ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
    echo "♻️ Updated PATH block in '${target_file}'." >&2
  else
    printf '\n%s\n%s\n%s\n' "$begin_marker" "$block_content" "$end_marker" >> "$target_file"
    echo "✅ Appended PATH block to '${target_file}'." >&2
  fi
  echo "↩️ Function exit: write_path_block" >&2
}

export_path_main() {
  echo "↪️ Function entry: export_path_main" >&2
  if [ "$EXPORT_PATH" = "" ]; then
    echo "ℹ️ export_path is empty; skipping PATH export." >&2
    echo "↩️ Function exit: export_path_main" >&2
    return
  fi
  local target_files
  target_files="$(build_export_path_list)"
  if [ -z "$target_files" ]; then
    echo "ℹ️ No target files for PATH export." >&2
    echo "↩️ Function exit: export_path_main" >&2
    return
  fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    write_path_block "$f"
  done <<< "$target_files"
  echo "↩️ Function exit: export_path_main" >&2
}

create_symlink() {
  echo "↪️ Function entry: create_symlink" >&2
  if [[ "$SYMLINK" != true ]]; then
    echo "ℹ️ symlink=false; skipping symlink creation." >&2
    echo "↩️ Function exit: create_symlink" >&2
    return
  fi
  if [ "$CONDA_DIR" = "/opt/conda" ]; then
    echo "ℹ️ conda_dir is already /opt/conda; no symlink needed." >&2
    echo "↩️ Function exit: create_symlink" >&2
    return
  fi
  if [ -d "/opt/conda" ] && [ ! -L "/opt/conda" ]; then
    echo "⛔ /opt/conda exists as a real directory; cannot create symlink. Disable symlink or remove the directory." >&2
    exit 1
  fi
  [ -L "/opt/conda" ] && rm -f "/opt/conda"
  ln -s "$CONDA_DIR" /opt/conda
  echo "✅ Created symlink /opt/conda -> $CONDA_DIR." >&2
  echo "↩️ Function exit: create_symlink" >&2
}

readonly _CONDA_INIT_SCRIPT_RELPATH="etc/profile.d/conda.sh"
readonly _MAMBA_INIT_SCRIPT_RELPATH="etc/profile.d/mamba.sh"

_LOGFILE_TMP="$(mktemp)"
exec 3>&1 4>&2
exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
echo "↪️ Script entry: Miniforge Installation Devcontainer Feature Installer" >&2
trap __cleanup__ EXIT


if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $@" >&2
  RC_FILES=()
  ACTIVATE_ENV=""
  CONDA_DIR=""
  DEBUG=""
  IF_EXISTS=""
  GROUP=""
  INSTALLER_DIR=""
  INTERACTIVE=""
  LOGFILE=""
  CONDA_VERSION=""
  KEEP_INSTALLER=""
  SET_PERMISSIONS=""
  UPDATE_BASE=""
  USERS=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --rc_files) shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do RC_FILES+=("$1"); echo "📩 Read argument 'rc_files': '${1}'" >&2; shift; done;;
      --activate_env) shift; ACTIVATE_ENV="$1"; echo "📩 Read argument 'activate_env': '${ACTIVATE_ENV}'" >&2; shift;;
      --conda_dir) shift; CONDA_DIR="$1"; echo "📩 Read argument 'conda_dir': '${CONDA_DIR}'" >&2; shift;;
      --debug) shift; DEBUG=true; echo "📩 Read argument 'debug': '${DEBUG}'" >&2;;
      --if_exists) shift; IF_EXISTS="$1"; echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2; shift;;
      --group) shift; GROUP="$1"; echo "📩 Read argument 'group': '${GROUP}'" >&2; shift;;
      --install) shift; echo "⚠️ --install is deprecated; use --if_exists. Ignored." >&2;;
      --installer_dir) shift; INSTALLER_DIR="$1"; echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2; shift;;
      --interactive) shift; INTERACTIVE=true; echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2;;
      --keep_installer) shift; KEEP_INSTALLER=true; echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2;;
      --logfile) shift; LOGFILE="$1"; echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2; shift;;
      --conda_version) shift; CONDA_VERSION="$1"; echo "📩 Read argument 'conda_version': '${CONDA_VERSION}'" >&2; shift;;
      --set_permissions) shift; SET_PERMISSIONS=true; echo "📩 Read argument 'set_permissions': '${SET_PERMISSIONS}'" >&2;;
      --update_base) shift; UPDATE_BASE=true; echo "📩 Read argument 'update_base': '${UPDATE_BASE}'" >&2;;
      --export_path) shift; EXPORT_PATH="$1"; echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2; shift;;
      --symlink) shift; SYMLINK=true; echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2;;
      --users) shift; USERS="$1"; echo "📩 Read argument 'users': '${USERS}'" >&2; shift;;
      --help|-h) __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
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
  [ "${CONDA_DIR+defined}" ] && echo "📩 Read argument 'conda_dir': '${CONDA_DIR}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${DOWNLOAD+defined}" ] && echo "📩 Read argument 'download (deprecated)': '${DOWNLOAD}'" >&2
  [ "${IF_EXISTS+defined}" ] && echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
  [ "${GROUP+defined}" ] && echo "📩 Read argument 'group': '${GROUP}'" >&2
  [ "${INSTALL+defined}" ] && echo "⚠️ 'INSTALL' env var is deprecated; use IF_EXISTS." >&2
  [ "${INSTALLER_DIR+defined}" ] && echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
  [ "${INTERACTIVE+defined}" ] && echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
  [ "${KEEP_INSTALLER+defined}" ] && echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${CONDA_VERSION+defined}" ] && echo "📩 Read argument 'conda_version': '${CONDA_VERSION}'" >&2
  [ "${REINSTALL+defined}" ] && echo "⚠️ 'REINSTALL' env var is deprecated; use IF_EXISTS=uninstall." >&2
  [ "${SET_PERMISSIONS+defined}" ] && echo "📩 Read argument 'set_permissions': '${SET_PERMISSIONS}'" >&2
  [ "${UPDATE_BASE+defined}" ] && echo "📩 Read argument 'update_base': '${UPDATE_BASE}'" >&2
  [ "${EXPORT_PATH+defined}" ] && echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
  [ "${SYMLINK+defined}" ] && echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
  [ "${USERS+defined}" ] && echo "📩 Read argument 'users': '${USERS}'" >&2
fi
[[ "$DEBUG" == true ]] && set -x
{ [ "${RC_FILES+isset}" != "isset" ] || [ ${#RC_FILES[@]} -eq 0 ]; } && { echo "ℹ️ Argument 'RC_FILES' set to default value '()'." >&2; RC_FILES=(); }
[ -z "${ACTIVATE_ENV-}" ] && { echo "ℹ️ Argument 'ACTIVATE_ENV' set to default value 'base'." >&2; ACTIVATE_ENV="base"; }
[ -z "${CONDA_DIR-}" ] && { echo "ℹ️ Argument 'CONDA_DIR' set to default value '/opt/conda'." >&2; CONDA_DIR="/opt/conda"; }
[ -z "${DEBUG-}" ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2; DEBUG=false; }
[ -z "${IF_EXISTS-}" ] && { echo "ℹ️ Argument 'IF_EXISTS' set to default value 'skip'." >&2; IF_EXISTS="skip"; }
[ -z "${GROUP-}" ] && { echo "ℹ️ Argument 'GROUP' set to default value 'conda'." >&2; GROUP="conda"; }
[ -z "${INSTALLER_DIR-}" ] && { echo "ℹ️ Argument 'INSTALLER_DIR' set to default value '/tmp/miniforge-installer'." >&2; INSTALLER_DIR="/tmp/miniforge-installer"; }
[ -z "${INTERACTIVE-}" ] && { echo "ℹ️ Argument 'INTERACTIVE' set to default value 'false'." >&2; INTERACTIVE=false; }
[ -z "${KEEP_INSTALLER-}" ] && { echo "ℹ️ Argument 'KEEP_INSTALLER' set to default value 'false'." >&2; KEEP_INSTALLER=false; }
[ -z "${LOGFILE-}" ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2; LOGFILE=""; }
[ -z "${CONDA_VERSION-}" ] && { echo "ℹ️ Argument 'CONDA_VERSION' set to default value 'latest'." >&2; CONDA_VERSION="latest"; }
[ -z "${SET_PERMISSIONS-}" ] && { echo "ℹ️ Argument 'SET_PERMISSIONS' set to default value 'false'." >&2; SET_PERMISSIONS=false; }
[ -z "${UPDATE_BASE-}" ] && { echo "ℹ️ Argument 'UPDATE_BASE' set to default value 'false'." >&2; UPDATE_BASE=false; }
[ -z "${EXPORT_PATH+x}" ] && { echo "ℹ️ Argument 'EXPORT_PATH' set to default value 'auto'." >&2; EXPORT_PATH="auto"; }
[ -z "${SYMLINK+x}" ] && { echo "ℹ️ Argument 'SYMLINK' set to default value 'false'." >&2; SYMLINK=false; }
[ -z "${USERS-}" ] && { echo "ℹ️ Argument 'USERS' set to default value '$(id -nu)'." >&2; USERS="$(id -nu)"; }
IFS=',' read -ra _USERS_ARR <<< "$USERS"


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

if [[ -f "${CONDA_DIR}/bin/conda" ]] || command -v conda >/dev/null 2>&1; then
    echo "⚠️ Conda installation found at '$CONDA_DIR'." >&2
    # Version-match idempotency: if installed conda version already matches the
    # resolved version, skip silently regardless of if_exists.
    _installed_ver="$("${CONDA_DIR}/bin/conda" --version 2>/dev/null | awk '{print $NF}')" || true
    if [[ -n "$_installed_ver" && "$_installed_ver" == "$RESOLVED_CONDA_VERSION" ]]; then
        echo "ℹ️ Installed conda version '${_installed_ver}' matches resolved version '${RESOLVED_CONDA_VERSION}'. Skipping install and continuing to post-install steps." >&2
    else
      case "$IF_EXISTS" in
        skip)
          echo "⏭️ if_exists=skip: existing conda detected; skipping install and continuing to post-install steps." >&2
          ;;
        fail)
          echo "⛔ if_exists=fail: conda already installed at '$CONDA_DIR'. Remove it first or set if_exists=skip/uninstall." >&2
          exit 1
          ;;
        uninstall)
          echo "ℹ️ if_exists=uninstall: uninstalling existing conda, then installing fresh." >&2
          set_executable_paths --verify
          uninstall_miniforge
          install_miniforge
          ;;
        update)
          echo "⛔ if_exists=update: not yet implemented." >&2
          exit 1
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
