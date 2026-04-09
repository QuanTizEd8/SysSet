#!/usr/bin/env bash
set -euo pipefail

__usage__() {
  echo "Usage:" >&2
  echo "  --activates (array): " >&2
  echo "  --active_env (string): This adds `conda activate <env>` to the shell configuration files
  specified in the `activates` parameter,
  and thus only has an effect if the `activates` parameter is set.
  " >&2
  echo "  --conda_activation_script_path (string): The path is relative to the conda installation directory.
  This is a constant and does not need to be changed
  unless Miniforge changes this path in the future.
  " >&2
  echo "  --conda_dir (string): This is the directory where conda will be installed.
  It corresponds to the `CONDA_DIR` environment variable.
  " >&2
  echo "  --debug (boolean): " >&2
  echo "  --download (boolean): " >&2
  echo "  --group (string): " >&2
  echo "  --install (boolean): Raises an error if conda is already installed.
  " >&2
  echo "  --installer_dir (string): This is the directory where the Miniforge installer will be downloaded.
  " >&2
  echo "  --interactive (boolean): This allows the installer to prompt the user.
  The default is to run the installer in non-interactive mode.
  " >&2
  echo "  --logfile (string): " >&2
  echo "  --mamba_activation_script_path (string): The path is relative to the conda installation directory.
  This is a constant and does not need to be changed
  unless Miniforge changes this path in the future.
  " >&2
  echo "  --miniforge_name (string): " >&2
  echo "  --miniforge_version (string): If not specified, the latest version will be installed.
  " >&2
  echo "  --no_clean (boolean): " >&2
  echo "  --reinstall (boolean): Same as 'install', but uninstall first if conda is already installed.
  " >&2
  echo "  --set_permission (boolean): This is done by adding the '--user' to the conda '--group'
  and setting the group ownership of the conda directory.
  " >&2
  echo "  --update_base (boolean): This is done by running `conda update --all`.
  This is not recommended for production environments.
  " >&2
  echo "  --update_path (boolean): Write /etc/profile.d/conda_path.sh so conda is
  available in subsequent shell sessions and Dockerfile RUN layers.
  " >&2
  echo "  --user (string): This user must already exist.
  If not specified, it defaults to the real user running this script.
  " >&2
  echo "  --require_root (string): Whether root is required ('auto', 'true', 'false').
  'auto' infers from the conda_dir prefix.
  " >&2
  exit 0
}

__cleanup__() {
  echo "↪️ Function entry: __cleanup__" >&2
  if [[ "${NO_CLEAN-}" == false ]]; then
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
  local conda_script="$CONDA_DIR/$CONDA_ACTIVATION_SCRIPT_PATH"
  local mamba_script="$CONDA_DIR/$MAMBA_ACTIVATION_SCRIPT_PATH"
  lines=(
      ". '$conda_script'"
      ". '$mamba_script'"
  )
  if [[ -n "$ACTIVE_ENV" ]]; then
      lines+=("conda activate $ACTIVE_ENV")
  fi
  for path in "${ACTIVATES[@]}"; do
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
  if [[ "$MINIFORGE_VERSION" == "latest" ]]; then
      installer_url="https://github.com/conda-forge/miniforge/releases/latest/download/${INSTALLER_FILENAME}"
      checksum_url=""  # TODO: Find a way to get the checksum URL for the latest version.
  else
      installer_url="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${INSTALLER_FILENAME}"
      checksum_url="$installer_url.sha256"
  fi
  mkdir -p "$INSTALLER_DIR"
  echo "📥 Downloading installer from $installer_url" >&2
  curl --fail --location --retry 3 --output "$INSTALLER" "$installer_url"
  if [[ -n "$checksum_url" ]]; then
      curl --fail --location --retry 3 --output "$CHECKSUM" "$checksum_url"
  fi
  if [[ -n "$checksum_url" ]]; then
      verify_miniforge
  fi
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
  case "$REQUIRE_ROOT" in
    true)  _require=true ;;
    false) _require=false ;;
    auto)
      case "$CONDA_DIR" in
        /opt/*|/usr/*|/var/*|/srv/*|/snap/*) _require=true ;;
        *) _require=false ;;
      esac
      ;;
    *) echo "⛔ Invalid value for 'require_root': '$REQUIRE_ROOT'. Use 'auto', 'true', or 'false'." >&2; exit 1 ;;
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
  if [[ "$UPDATE_PATH" == true ]]; then
      echo "ℹ️ Writing /etc/profile.d/conda_path.sh" >&2
      printf 'export PATH="%s/bin:${PATH}"\n' "$CONDA_DIR" > /etc/profile.d/conda_path.sh
      echo "✅ /etc/profile.d/conda_path.sh written." >&2
  fi
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
  if [[ "$MINIFORGE_VERSION" == "latest" ]]; then
      INSTALLER_FILENAME="${MINIFORGE_NAME}-${installer_platform}.sh"
  else
      INSTALLER_FILENAME="${MINIFORGE_NAME}-${MINIFORGE_VERSION}-${installer_platform}.sh"
  fi
  INSTALLER="${INSTALLER_DIR}/${INSTALLER_FILENAME}"
  CHECKSUM="${INSTALLER}.sha256"
  echo "↩️ Function exit: set_installer_filename" >&2
}

set_permission() {
  echo "↪️ Function entry: set_permission" >&2
  echo "🔐 Setting permissions for conda directory."
  getent group "$GROUP" >/dev/null || groupadd -r "$GROUP"
  id -nG "$USER" | grep -qw "$GROUP" || usermod -a -G "$GROUP" "$USER"
  chown -R "$USER:$GROUP" "$CONDA_DIR"
  chmod -R g+r+w "$CONDA_DIR"
  find "$CONDA_DIR" -type d -print0 | xargs -n 1 -0 chmod g+s
  echo "↩️ Function exit: set_permission" >&2
}

uninstall_miniforge() {
  echo "↪️ Function entry: uninstall_miniforge" >&2
  echo "🗑 Uninstalling conda (Miniforge)."
  "$CONDA_EXEC" init --reverse
  rm -rf "$("$CONDA_EXEC" info --base)"
  rm -f "$HOME/.condarc"
  rm -rf "$HOME/.conda"
  user_home=$(getent passwd "$USER" | cut -d: -f6)
  rm -rf "$user_home/.condarc"
  rm -rf "$user_home/.conda"
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


_LOGFILE_TMP="$(mktemp)"
exec 3>&1 4>&2
exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
echo "↪️ Script entry: Miniforge Installation Devcontainer Feature Installer" >&2
trap __cleanup__ EXIT


if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $@" >&2
  ACTIVATES=()
  ACTIVE_ENV=""
  CONDA_ACTIVATION_SCRIPT_PATH=""
  CONDA_DIR=""
  DEBUG=""
  DOWNLOAD=""
  GROUP=""
  INSTALL=""
  INSTALLER_DIR=""
  INTERACTIVE=""
  LOGFILE=""
  MAMBA_ACTIVATION_SCRIPT_PATH=""
  MINIFORGE_NAME=""
  MINIFORGE_VERSION=""
  NO_CLEAN=""
  REINSTALL=""
  REQUIRE_ROOT=""
  SET_PERMISSION=""
  UPDATE_BASE=""
  UPDATE_PATH=""
  USER=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --activates) shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do ACTIVATES+=("$1"); echo "📩 Read argument 'activates': '${1}'" >&2; shift; done;;
      --active_env) shift; ACTIVE_ENV="$1"; echo "📩 Read argument 'active_env': '${ACTIVE_ENV}'" >&2; shift;;
      --conda_activation_script_path) shift; CONDA_ACTIVATION_SCRIPT_PATH="$1"; echo "📩 Read argument 'conda_activation_script_path': '${CONDA_ACTIVATION_SCRIPT_PATH}'" >&2; shift;;
      --conda_dir) shift; CONDA_DIR="$1"; echo "📩 Read argument 'conda_dir': '${CONDA_DIR}'" >&2; shift;;
      --debug) shift; DEBUG=true; echo "📩 Read argument 'debug': '${DEBUG}'" >&2;;
      --download) shift; DOWNLOAD=true; echo "📩 Read argument 'download': '${DOWNLOAD}'" >&2;;
      --group) shift; GROUP="$1"; echo "📩 Read argument 'group': '${GROUP}'" >&2; shift;;
      --install) shift; INSTALL=true; echo "📩 Read argument 'install': '${INSTALL}'" >&2;;
      --installer_dir) shift; INSTALLER_DIR="$1"; echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2; shift;;
      --interactive) shift; INTERACTIVE=true; echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2;;
      --logfile) shift; LOGFILE="$1"; echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2; shift;;
      --mamba_activation_script_path) shift; MAMBA_ACTIVATION_SCRIPT_PATH="$1"; echo "📩 Read argument 'mamba_activation_script_path': '${MAMBA_ACTIVATION_SCRIPT_PATH}'" >&2; shift;;
      --miniforge_name) shift; MINIFORGE_NAME="$1"; echo "📩 Read argument 'miniforge_name': '${MINIFORGE_NAME}'" >&2; shift;;
      --miniforge_version) shift; MINIFORGE_VERSION="$1"; echo "📩 Read argument 'miniforge_version': '${MINIFORGE_VERSION}'" >&2; shift;;
      --no_clean) shift; NO_CLEAN=true; echo "📩 Read argument 'no_clean': '${NO_CLEAN}'" >&2;;
      --reinstall) shift; REINSTALL=true; echo "📩 Read argument 'reinstall': '${REINSTALL}'" >&2;;
      --require_root) shift; REQUIRE_ROOT="$1"; echo "📩 Read argument 'require_root': '${REQUIRE_ROOT}'" >&2; shift;;
      --set_permission) shift; SET_PERMISSION=true; echo "📩 Read argument 'set_permission': '${SET_PERMISSION}'" >&2;;
      --update_base) shift; UPDATE_BASE=true; echo "📩 Read argument 'update_base': '${UPDATE_BASE}'" >&2;;
      --update_path) shift; UPDATE_PATH=true; echo "📩 Read argument 'update_path': '${UPDATE_PATH}'" >&2;;
      --user) shift; USER="$1"; echo "📩 Read argument 'user': '${USER}'" >&2; shift;;
      --help|-h) __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  if [ "${ACTIVATES+defined}" ]; then
    if [ -n "${ACTIVATES-}" ]; then
      echo "ℹ️ Parse 'activates' into array: '${ACTIVATES}'" >&2
    fi
    mapfile -t _tmp_array < <(printf '%s' "${ACTIVATES-}" | sed 's/ :: /\n/g')
    ACTIVATES=("${_tmp_array[@]}")
    for _item in "${ACTIVATES[@]}"; do
      echo "📩 Read argument 'activates': '${_item}'" >&2
    done
    unset _item
    unset _tmp_array
  fi
  [ "${ACTIVE_ENV+defined}" ] && echo "📩 Read argument 'active_env': '${ACTIVE_ENV}'" >&2
  [ "${CONDA_ACTIVATION_SCRIPT_PATH+defined}" ] && echo "📩 Read argument 'conda_activation_script_path': '${CONDA_ACTIVATION_SCRIPT_PATH}'" >&2
  [ "${CONDA_DIR+defined}" ] && echo "📩 Read argument 'conda_dir': '${CONDA_DIR}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${DOWNLOAD+defined}" ] && echo "📩 Read argument 'download': '${DOWNLOAD}'" >&2
  [ "${GROUP+defined}" ] && echo "📩 Read argument 'group': '${GROUP}'" >&2
  [ "${INSTALL+defined}" ] && echo "📩 Read argument 'install': '${INSTALL}'" >&2
  [ "${INSTALLER_DIR+defined}" ] && echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
  [ "${INTERACTIVE+defined}" ] && echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${MAMBA_ACTIVATION_SCRIPT_PATH+defined}" ] && echo "📩 Read argument 'mamba_activation_script_path': '${MAMBA_ACTIVATION_SCRIPT_PATH}'" >&2
  [ "${MINIFORGE_NAME+defined}" ] && echo "📩 Read argument 'miniforge_name': '${MINIFORGE_NAME}'" >&2
  [ "${MINIFORGE_VERSION+defined}" ] && echo "📩 Read argument 'miniforge_version': '${MINIFORGE_VERSION}'" >&2
  [ "${NO_CLEAN+defined}" ] && echo "📩 Read argument 'no_clean': '${NO_CLEAN}'" >&2
  [ "${REINSTALL+defined}" ] && echo "📩 Read argument 'reinstall': '${REINSTALL}'" >&2
  [ "${REQUIRE_ROOT+defined}" ] && echo "📩 Read argument 'require_root': '${REQUIRE_ROOT}'" >&2
  [ "${SET_PERMISSION+defined}" ] && echo "📩 Read argument 'set_permission': '${SET_PERMISSION}'" >&2
  [ "${UPDATE_BASE+defined}" ] && echo "📩 Read argument 'update_base': '${UPDATE_BASE}'" >&2
  [ "${UPDATE_PATH+defined}" ] && echo "📩 Read argument 'update_path': '${UPDATE_PATH}'" >&2
  [ "${USER+defined}" ] && echo "📩 Read argument 'user': '${USER}'" >&2
fi
[[ "$DEBUG" == true ]] && set -x
{ [ "${ACTIVATES+isset}" != "isset" ] || [ ${#ACTIVATES[@]} -eq 0 ]; } && { echo "ℹ️ Argument 'ACTIVATES' set to default value '()'." >&2; ACTIVATES=(); }
[ -z "${ACTIVE_ENV-}" ] && { echo "ℹ️ Argument 'ACTIVE_ENV' set to default value 'base'." >&2; ACTIVE_ENV="base"; }
[ -z "${CONDA_ACTIVATION_SCRIPT_PATH-}" ] && { echo "ℹ️ Argument 'CONDA_ACTIVATION_SCRIPT_PATH' set to default value 'etc/profile.d/conda.sh'." >&2; CONDA_ACTIVATION_SCRIPT_PATH="etc/profile.d/conda.sh"; }
[ -z "${CONDA_DIR-}" ] && { echo "ℹ️ Argument 'CONDA_DIR' set to default value '/opt/conda'." >&2; CONDA_DIR="/opt/conda"; }
[ -z "${DEBUG-}" ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2; DEBUG=false; }
[ -z "${DOWNLOAD-}" ] && { echo "ℹ️ Argument 'DOWNLOAD' set to default value 'false'." >&2; DOWNLOAD=false; }
[ -z "${GROUP-}" ] && { echo "ℹ️ Argument 'GROUP' set to default value 'conda'." >&2; GROUP="conda"; }
[ -z "${INSTALL-}" ] && { echo "ℹ️ Argument 'INSTALL' set to default value 'false'." >&2; INSTALL=false; }
[ -z "${INSTALLER_DIR-}" ] && { echo "ℹ️ Argument 'INSTALLER_DIR' set to default value '/tmp/miniforge-installer'." >&2; INSTALLER_DIR="/tmp/miniforge-installer"; }
[ -z "${INTERACTIVE-}" ] && { echo "ℹ️ Argument 'INTERACTIVE' set to default value 'false'." >&2; INTERACTIVE=false; }
[ -z "${LOGFILE-}" ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2; LOGFILE=""; }
[ -z "${MAMBA_ACTIVATION_SCRIPT_PATH-}" ] && { echo "ℹ️ Argument 'MAMBA_ACTIVATION_SCRIPT_PATH' set to default value 'etc/profile.d/mamba.sh'." >&2; MAMBA_ACTIVATION_SCRIPT_PATH="etc/profile.d/mamba.sh"; }
[ -z "${MINIFORGE_NAME-}" ] && { echo "ℹ️ Argument 'MINIFORGE_NAME' set to default value 'Miniforge3'." >&2; MINIFORGE_NAME="Miniforge3"; }
[ -z "${MINIFORGE_VERSION-}" ] && { echo "ℹ️ Argument 'MINIFORGE_VERSION' set to default value 'latest'." >&2; MINIFORGE_VERSION="latest"; }
[ -z "${NO_CLEAN-}" ] && { echo "ℹ️ Argument 'NO_CLEAN' set to default value 'false'." >&2; NO_CLEAN=false; }
[ -z "${REINSTALL-}" ] && { echo "ℹ️ Argument 'REINSTALL' set to default value 'false'." >&2; REINSTALL=false; }
[ -z "${REQUIRE_ROOT-}" ] && { echo "ℹ️ Argument 'REQUIRE_ROOT' set to default value 'auto'." >&2; REQUIRE_ROOT="auto"; }
[ -z "${SET_PERMISSION-}" ] && { echo "ℹ️ Argument 'SET_PERMISSION' set to default value 'false'." >&2; SET_PERMISSION=false; }
[ -z "${UPDATE_BASE-}" ] && { echo "ℹ️ Argument 'UPDATE_BASE' set to default value 'false'." >&2; UPDATE_BASE=false; }
[ -z "${UPDATE_PATH-}" ] && { echo "ℹ️ Argument 'UPDATE_PATH' set to default value 'true'." >&2; UPDATE_PATH=true; }
[ -z "${USER-}" ] && { echo "ℹ️ Argument 'USER' set to default value '$(id -nu)'." >&2; USER="$(id -nu)"; }


check_root_requirement
set_executable_paths

if [[ "$DOWNLOAD" == true || "$INSTALL" == true || "$REINSTALL" == true ]]; then
    set_installer_filename
fi
if [[ "$DOWNLOAD" == true ]]; then download_miniforge; fi
if [[ "$DOWNLOAD" == true || "$INSTALL" == true || "$REINSTALL" == true ]]; then
    if [[ -f "$CHECKSUM" ]]; then
        verify_miniforge
    else
        echo "⚠️ Checksum file not found. Skipping verification." >&2
    fi
fi
if [[ "$INSTALL" == true || "$REINSTALL" == true ]]; then
    if command -v conda >/dev/null 2>&1; then
        echo "⚠️ Conda installation found."
        if [[ "$REINSTALL" != true ]]; then
            echo "⏩ Conda is already available."
        else
            uninstall_miniforge
            install_miniforge
        fi
    else
        install_miniforge
    fi
fi

set_executable_paths --verify

if [[ ${#ACTIVATES[@]} -gt 0 ]]; then add_activation_to_rcfile; fi
if [[ "$UPDATE_BASE" == true ]]; then
    echo "⚠️ Updating base conda environment."
    "$MAMBA_EXEC" update -n base --all -y
fi

if [[ "$SET_PERMISSION" == true ]]; then set_permission; fi

echo "✅ Conda installation complete."
echo "↩️ Script exit: Miniforge Installation Devcontainer Feature Installer" >&2
