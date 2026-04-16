#!/usr/bin/env bash
set -euo pipefail
__usage__() {
  echo "Usage:" >&2
  echo "  --conda_dir (string): Path to the conda installation directory." >&2
  echo "    Leave empty to auto-detect via conda in PATH." >&2
  echo "  --env_files (string): Paths to conda environment YAML files." >&2
  echo "    Separate multiple paths with ' :: '." >&2
  echo "  --env_dirs (string): Paths to directories containing conda environment YAML files." >&2
  echo "    Separate multiple paths with ' :: '." >&2
  echo "  --env_name (string): Name of a conda environment to create/update from inline options." >&2
  echo "  --packages (string): Space-separated conda packages for the inline env (requires env_name)." >&2
  echo "  --python_version (string): Python version for the inline env (e.g. '3.11')." >&2
  echo "  --channels (string): Conda channels to add. Separate with ' :: '." >&2
  echo "  --strict_channel_priority (boolean): Set channel_priority to strict." >&2
  echo "  --pip_requirements_files (string): Pip requirements files. Separate with ' :: '." >&2
  echo "  --pip_env (string): Conda env to pip-install requirements into (default: each env's own)." >&2
  echo "  --post_env_script (string): Script run after each env create/update; receives env name as \$1." >&2
  echo "  --solver (string): Solver to use: 'auto' (default), 'mamba', or 'conda'." >&2
  echo "  --keep_cache (boolean): Skip 'conda clean' after setup." >&2
  echo "  --debug (boolean): Enable debug output." >&2
  echo "  --logfile (string): Log all output to this file in addition to console." >&2
  exit 0
}

discover_conda() {
  echo "↪️ Function entry: discover_conda" >&2
  CONDA_EXEC="${CONDA_DIR}/bin/conda"
  MAMBA_EXEC="${CONDA_DIR}/bin/mamba"
  if [[ -n "$CONDA_DIR" ]] && [[ -f "$CONDA_EXEC" ]]; then
    echo "🎛 Conda executable located at '$CONDA_EXEC'." >&2
  elif [[ -n "$CONDA_DIR" ]]; then
    echo "⛔ conda_dir was set to '$CONDA_DIR' but conda executable not found at '$CONDA_EXEC'." >&2
    exit 1
  elif command -v conda > /dev/null 2>&1; then
    CONDA_DIR="$(conda info --base)"
    CONDA_EXEC="${CONDA_DIR}/bin/conda"
    MAMBA_EXEC="${CONDA_DIR}/bin/mamba"
    echo "🔍 Auto-detected conda at '$CONDA_EXEC' (base: $CONDA_DIR)." >&2
  else
    echo "⛔ Conda not found. Set 'conda_dir' or ensure conda is on PATH." >&2
    echo "   Install conda first, e.g. with the install-miniforge feature." >&2
    exit 1
  fi
  if [[ ! -f "$MAMBA_EXEC" ]]; then
    echo "ℹ️ Mamba executable not found at '$MAMBA_EXEC'. Will use conda as fallback." >&2
    MAMBA_EXEC=""
  else
    echo "🎛 Mamba executable located at '$MAMBA_EXEC'." >&2
  fi
  echo "↩️ Function exit: discover_conda" >&2
}

resolve_solver() {
  echo "↪️ Function entry: resolve_solver" >&2
  case "$SOLVER" in
    mamba)
      if [[ -z "$MAMBA_EXEC" ]]; then
        echo "⚠️ Solver 'mamba' requested but mamba not found. Falling back to conda." >&2
        SOLVER_EXEC="$CONDA_EXEC"
      else
        SOLVER_EXEC="$MAMBA_EXEC"
      fi
      ;;
    conda)
      SOLVER_EXEC="$CONDA_EXEC"
      ;;
    auto)
      if [[ -n "$MAMBA_EXEC" ]]; then
        SOLVER_EXEC="$MAMBA_EXEC"
        echo "ℹ️ Solver 'auto': using mamba." >&2
      else
        SOLVER_EXEC="$CONDA_EXEC"
        echo "ℹ️ Solver 'auto': using conda (mamba not available)." >&2
      fi
      ;;
    *)
      echo "⛔ Invalid value for 'solver': '$SOLVER'. Use 'auto', 'mamba', or 'conda'." >&2
      exit 1
      ;;
  esac
  echo "🎛 Solver executable: '$SOLVER_EXEC'." >&2
  echo "↩️ Function exit: resolve_solver" >&2
}

apply_channels() {
  echo "↪️ Function entry: apply_channels" >&2
  if [[ ${#CHANNELS[@]} -eq 0 ]] && [[ "$STRICT_CHANNEL_PRIORITY" == false ]]; then
    echo "ℹ️ No channels or channel priority changes requested." >&2
    echo "↩️ Function exit: apply_channels" >&2
    return
  fi
  for channel in "${CHANNELS[@]}"; do
    echo "📋 Adding channel: $channel" >&2
    "$CONDA_EXEC" config --add channels "$channel"
  done
  if [[ "$STRICT_CHANNEL_PRIORITY" == true ]]; then
    echo "📋 Setting channel_priority to strict." >&2
    "$CONDA_EXEC" config --set channel_priority strict
  fi
  echo "↩️ Function exit: apply_channels" >&2
}

create_or_update_env() {
  echo "↪️ Function entry: create_or_update_env" >&2
  local env_file=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env_file)
        shift
        env_file="$1"
        echo "📩 Read argument 'env_file': '${env_file}'" >&2
        shift
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
  [ -z "${env_file-}" ] && {
    echo "⛔ Missing required argument 'env_file'." >&2
    exit 1
  }
  local env_name
  env_name=$(grep -E '^name:' "$env_file" | head -1 | awk '{print $2}')
  local env_prefix
  if [ "$env_name" = "base" ]; then
    env_prefix="$CONDA_DIR"
  else
    env_prefix="$CONDA_DIR/envs/$env_name"
  fi
  if [ -n "$env_name" ] && [ -d "$env_prefix" ]; then
    echo "📦 Updating existing conda environment '$env_name' from '$env_file'." >&2
    "$SOLVER_EXEC" env update --file "$env_file" --yes
  else
    echo "📦 Creating conda environment from '$env_file'." >&2
    "$SOLVER_EXEC" env create --file "$env_file" --yes
  fi
  echo "↩️ Function exit: create_or_update_env" >&2
}

install_pip_requirements() {
  echo "↪️ Function entry: install_pip_requirements" >&2
  local env_name=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env_name)
        shift
        env_name="$1"
        echo "📩 Read argument 'env_name': '${env_name}'" >&2
        shift
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
  [ -z "${env_name-}" ] && {
    echo "⛔ Missing required argument 'env_name'." >&2
    exit 1
  }
  if [[ ${#PIP_REQUIREMENTS_FILES[@]} -eq 0 ]]; then
    echo "ℹ️ No pip requirements files specified." >&2
    echo "↩️ Function exit: install_pip_requirements" >&2
    return
  fi
  local pip_exec
  if [[ "$env_name" == "base" ]]; then
    pip_exec="${CONDA_DIR}/bin/pip"
  else
    pip_exec="${CONDA_DIR}/envs/${env_name}/bin/pip"
  fi
  if [[ ! -f "$pip_exec" ]]; then
    echo "⚠️ pip not found at '$pip_exec'. Skipping pip requirements for env '$env_name'." >&2
    echo "↩️ Function exit: install_pip_requirements" >&2
    return
  fi
  for req_file in "${PIP_REQUIREMENTS_FILES[@]}"; do
    echo "📦 Installing pip requirements from '$req_file' into env '$env_name'." >&2
    "$pip_exec" install -r "$req_file"
  done
  echo "↩️ Function exit: install_pip_requirements" >&2
}

run_post_env_script() {
  echo "↪️ Function entry: run_post_env_script" >&2
  local env_name=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env_name)
        shift
        env_name="$1"
        echo "📩 Read argument 'env_name': '${env_name}'" >&2
        shift
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
  [ -z "${env_name-}" ] && {
    echo "⛔ Missing required argument 'env_name'." >&2
    exit 1
  }
  if [[ -z "$POST_ENV_SCRIPT" ]]; then
    echo "↩️ Function exit: run_post_env_script" >&2
    return
  fi
  if [[ ! -f "$POST_ENV_SCRIPT" ]]; then
    echo "⛔ post_env_script not found: '$POST_ENV_SCRIPT'." >&2
    exit 1
  fi
  if [[ ! -x "$POST_ENV_SCRIPT" ]]; then
    echo "⛔ post_env_script is not executable: '$POST_ENV_SCRIPT'." >&2
    exit 1
  fi
  echo "▶️ Running post-env script '$POST_ENV_SCRIPT' for env '$env_name'." >&2
  "$POST_ENV_SCRIPT" "$env_name"
  echo "↩️ Function exit: run_post_env_script" >&2
}

setup_inline_env() {
  echo "↪️ Function entry: setup_inline_env" >&2
  local tmp_env_file
  tmp_env_file="$(mktemp --suffix=.yml)"
  printf 'name: %s\n' "$ENV_NAME" > "$tmp_env_file"
  printf 'dependencies:\n' >> "$tmp_env_file"
  if [[ -n "$PYTHON_VERSION" ]]; then
    printf '  - python=%s\n' "$PYTHON_VERSION" >> "$tmp_env_file"
  fi
  for pkg in $PACKAGES; do
    printf '  - %s\n' "$pkg" >> "$tmp_env_file"
  done
  echo "📋 Generated inline environment file:" >&2
  cat "$tmp_env_file" >&2
  create_or_update_env --env_file "$tmp_env_file"
  rm -f "$tmp_env_file"
  local _pip_target="${PIP_ENV:-$ENV_NAME}"
  install_pip_requirements --env_name "$_pip_target"
  run_post_env_script --env_name "$ENV_NAME"
  echo "↩️ Function exit: setup_inline_env" >&2
}

setup_environment() {
  echo "↪️ Function entry: setup_environment" >&2
  umask 0002
  for env_file in "${ENV_FILES[@]}"; do
    local env_name
    env_name=$(grep -E '^name:' "$env_file" | head -1 | awk '{print $2}')
    create_or_update_env --env_file "$env_file"
    local _pip_target="${PIP_ENV:-$env_name}"
    install_pip_requirements --env_name "$_pip_target"
    run_post_env_script --env_name "$env_name"
  done
  for env_dir in "${ENV_DIRS[@]}"; do
    while IFS= read -r env_file; do
      local env_name
      env_name=$(grep -E '^name:' "$env_file" | head -1 | awk '{print $2}')
      create_or_update_env --env_file "$env_file"
      local _pip_target="${PIP_ENV:-$env_name}"
      install_pip_requirements --env_name "$_pip_target"
      run_post_env_script --env_name "$env_name"
    done < <(find "$env_dir" -type f \( -name "*.yml" -o -name "*.yaml" \) | sort)
  done
  echo "↩️ Function exit: setup_environment" >&2
}

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: Conda Environment Devcontainer Feature Installer" >&2
trap 'logging__cleanup' EXIT
if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  CHANNELS=()
  CONDA_DIR=""
  DEBUG=""
  ENV_DIRS=()
  ENV_FILES=()
  ENV_NAME=""
  LOGFILE=""
  KEEP_CACHE=""
  PACKAGES=""
  PIP_ENV=""
  PIP_REQUIREMENTS_FILES=()
  POST_ENV_SCRIPT=""
  PYTHON_VERSION=""
  SOLVER=""
  STRICT_CHANNEL_PRIORITY=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --channels)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          CHANNELS+=("$1")
          echo "📩 Read argument 'channels': '${1}'" >&2
          shift
        done
        ;;
      --conda_dir)
        shift
        CONDA_DIR="$1"
        echo "📩 Read argument 'conda_dir': '${CONDA_DIR}'" >&2
        shift
        ;;
      --debug)
        shift
        DEBUG=true
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        ;;
      --env_dirs)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          ENV_DIRS+=("$1")
          echo "📩 Read argument 'env_dirs': '${1}'" >&2
          shift
        done
        ;;
      --env_files)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          ENV_FILES+=("$1")
          echo "📩 Read argument 'env_files': '${1}'" >&2
          shift
        done
        ;;
      --env_name)
        shift
        ENV_NAME="$1"
        echo "📩 Read argument 'env_name': '${ENV_NAME}'" >&2
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      --keep_cache)
        shift
        KEEP_CACHE=true
        echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
        ;;
      --packages)
        shift
        PACKAGES="$1"
        echo "📩 Read argument 'packages': '${PACKAGES}'" >&2
        shift
        ;;
      --pip_env)
        shift
        PIP_ENV="$1"
        echo "📩 Read argument 'pip_env': '${PIP_ENV}'" >&2
        shift
        ;;
      --pip_requirements_files)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          PIP_REQUIREMENTS_FILES+=("$1")
          echo "📩 Read argument 'pip_requirements_files': '${1}'" >&2
          shift
        done
        ;;
      --post_env_script)
        shift
        POST_ENV_SCRIPT="$1"
        echo "📩 Read argument 'post_env_script': '${POST_ENV_SCRIPT}'" >&2
        shift
        ;;
      --python_version)
        shift
        PYTHON_VERSION="$1"
        echo "📩 Read argument 'python_version': '${PYTHON_VERSION}'" >&2
        shift
        ;;
      --solver)
        shift
        SOLVER="$1"
        echo "📩 Read argument 'solver': '${SOLVER}'" >&2
        shift
        ;;
      --strict_channel_priority)
        shift
        STRICT_CHANNEL_PRIORITY=true
        echo "📩 Read argument 'strict_channel_priority': '${STRICT_CHANNEL_PRIORITY}'" >&2
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
  if [ "${CHANNELS+defined}" ]; then
    if [ -n "${CHANNELS-}" ]; then
      echo "ℹ️ Parse 'channels' into array: '${CHANNELS}'" >&2
    fi
    mapfile -t _tmp_array < <(printf '%s' "${CHANNELS-}" | sed 's/ :: /\n/g')
    CHANNELS=("${_tmp_array[@]}")
    for _item in "${CHANNELS[@]}"; do
      echo "📩 Read argument 'channels': '${_item}'" >&2
    done
    unset _item
    unset _tmp_array
  fi
  [ "${CONDA_DIR+defined}" ] && echo "📩 Read argument 'conda_dir': '${CONDA_DIR}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  if [ "${ENV_DIRS+defined}" ]; then
    if [ -n "${ENV_DIRS-}" ]; then
      echo "ℹ️ Parse 'env_dirs' into array: '${ENV_DIRS}'" >&2
    fi
    mapfile -t _tmp_array < <(printf '%s' "${ENV_DIRS-}" | sed 's/ :: /\n/g')
    ENV_DIRS=("${_tmp_array[@]}")
    for _item in "${ENV_DIRS[@]}"; do
      echo "📩 Read argument 'env_dirs': '${_item}'" >&2
    done
    unset _item
    unset _tmp_array
  fi
  if [ "${ENV_FILES+defined}" ]; then
    if [ -n "${ENV_FILES-}" ]; then
      echo "ℹ️ Parse 'env_files' into array: '${ENV_FILES}'" >&2
    fi
    mapfile -t _tmp_array < <(printf '%s' "${ENV_FILES-}" | sed 's/ :: /\n/g')
    ENV_FILES=("${_tmp_array[@]}")
    for _item in "${ENV_FILES[@]}"; do
      echo "📩 Read argument 'env_files': '${_item}'" >&2
    done
    unset _item
    unset _tmp_array
  fi
  [ "${ENV_NAME+defined}" ] && echo "📩 Read argument 'env_name': '${ENV_NAME}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${KEEP_CACHE+defined}" ] && echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
  [ "${PACKAGES+defined}" ] && echo "📩 Read argument 'packages': '${PACKAGES}'" >&2
  [ "${PIP_ENV+defined}" ] && echo "📩 Read argument 'pip_env': '${PIP_ENV}'" >&2
  if [ "${PIP_REQUIREMENTS_FILES+defined}" ]; then
    if [ -n "${PIP_REQUIREMENTS_FILES-}" ]; then
      echo "ℹ️ Parse 'pip_requirements_files' into array: '${PIP_REQUIREMENTS_FILES}'" >&2
    fi
    mapfile -t _tmp_array < <(printf '%s' "${PIP_REQUIREMENTS_FILES-}" | sed 's/ :: /\n/g')
    PIP_REQUIREMENTS_FILES=("${_tmp_array[@]}")
    for _item in "${PIP_REQUIREMENTS_FILES[@]}"; do
      echo "📩 Read argument 'pip_requirements_files': '${_item}'" >&2
    done
    unset _item
    unset _tmp_array
  fi
  [ "${POST_ENV_SCRIPT+defined}" ] && echo "📩 Read argument 'post_env_script': '${POST_ENV_SCRIPT}'" >&2
  [ "${PYTHON_VERSION+defined}" ] && echo "📩 Read argument 'python_version': '${PYTHON_VERSION}'" >&2
  [ "${SOLVER+defined}" ] && echo "📩 Read argument 'solver': '${SOLVER}'" >&2
  [ "${STRICT_CHANNEL_PRIORITY+defined}" ] && echo "📩 Read argument 'strict_channel_priority': '${STRICT_CHANNEL_PRIORITY}'" >&2
fi
[[ "${DEBUG:-}" == true ]] && set -x
{ [ "${CHANNELS+isset}" != "isset" ] || [ ${#CHANNELS[@]} -eq 0 ]; } && {
  echo "ℹ️ Argument 'CHANNELS' set to default value '()'." >&2
  CHANNELS=()
}
[ -z "${CONDA_DIR-}" ] && {
  echo "ℹ️ Argument 'CONDA_DIR' set to default value ''." >&2
  CONDA_DIR=""
}
[ -z "${DEBUG-}" ] && {
  echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2
  DEBUG=false
}
{ [ "${ENV_DIRS+isset}" != "isset" ] || [ ${#ENV_DIRS[@]} -eq 0 ]; } && {
  echo "ℹ️ Argument 'ENV_DIRS' set to default value '()'." >&2
  ENV_DIRS=()
}
for elem in "${ENV_DIRS[@]}"; do
  [ -n "${elem-}" ] && [ ! -d "${elem}" ] && {
    echo "⛔ Directory argument to parameter 'env_dirs' not found: '${elem}'" >&2
    exit 1
  }
done
{ [ "${ENV_FILES+isset}" != "isset" ] || [ ${#ENV_FILES[@]} -eq 0 ]; } && {
  echo "ℹ️ Argument 'ENV_FILES' set to default value '()'." >&2
  ENV_FILES=()
}
for elem in "${ENV_FILES[@]}"; do
  [ -n "${elem-}" ] && [ ! -f "${elem}" ] && {
    echo "⛔ File argument to parameter 'env_files' not found: '${elem}'" >&2
    exit 1
  }
done
[ -z "${ENV_NAME-}" ] && {
  echo "ℹ️ Argument 'ENV_NAME' set to default value ''." >&2
  ENV_NAME=""
}
[ -z "${LOGFILE-}" ] && {
  echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2
  LOGFILE=""
}
[ -z "${KEEP_CACHE-}" ] && {
  echo "ℹ️ Argument 'KEEP_CACHE' set to default value 'false'." >&2
  KEEP_CACHE=false
}
[ -z "${PACKAGES-}" ] && {
  echo "ℹ️ Argument 'PACKAGES' set to default value ''." >&2
  PACKAGES=""
}
[ -z "${PIP_ENV-}" ] && {
  echo "ℹ️ Argument 'PIP_ENV' set to default value ''." >&2
  PIP_ENV=""
}
{ [ "${PIP_REQUIREMENTS_FILES+isset}" != "isset" ] || [ ${#PIP_REQUIREMENTS_FILES[@]} -eq 0 ]; } && {
  echo "ℹ️ Argument 'PIP_REQUIREMENTS_FILES' set to default value '()'." >&2
  PIP_REQUIREMENTS_FILES=()
}
for elem in "${PIP_REQUIREMENTS_FILES[@]}"; do
  [ -n "${elem-}" ] && [ ! -f "${elem}" ] && {
    echo "⛔ File argument to parameter 'pip_requirements_files' not found: '${elem}'" >&2
    exit 1
  }
done
[ -z "${POST_ENV_SCRIPT-}" ] && {
  echo "ℹ️ Argument 'POST_ENV_SCRIPT' set to default value ''." >&2
  POST_ENV_SCRIPT=""
}
[ -z "${PYTHON_VERSION-}" ] && {
  echo "ℹ️ Argument 'PYTHON_VERSION' set to default value ''." >&2
  PYTHON_VERSION=""
}
[ -z "${SOLVER-}" ] && {
  echo "ℹ️ Argument 'SOLVER' set to default value 'auto'." >&2
  SOLVER="auto"
}
[ -z "${STRICT_CHANNEL_PRIORITY-}" ] && {
  echo "ℹ️ Argument 'STRICT_CHANNEL_PRIORITY' set to default value 'false'." >&2
  STRICT_CHANNEL_PRIORITY=false
}
if [[ -n "$ENV_NAME" ]] && [[ -z "$PACKAGES" ]] && [[ -z "$PYTHON_VERSION" ]]; then
  echo "⛔ 'env_name' requires at least one of 'packages' or 'python_version' to be set." >&2
  exit 1
fi
ospkg__run --manifest "${_SELF_DIR}/../dependencies/base.yaml" --check_installed
discover_conda
resolve_solver
apply_channels
if [[ -n "$ENV_NAME" ]]; then setup_inline_env; fi
if [[ ${#ENV_FILES[@]} -gt 0 || ${#ENV_DIRS[@]} -gt 0 ]]; then setup_environment; fi
if [[ "$KEEP_CACHE" == false ]]; then
  echo "🧹 Cleaning up conda cache." >&2
  "$SOLVER_EXEC" clean --all -y
fi
echo "✅ Conda environment setup complete."
echo "↩️ Script exit: Conda Environment Devcontainer Feature Installer" >&2
