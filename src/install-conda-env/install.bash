#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$_SELF_DIR"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: Conda Environment" >&2
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
    echo "✅ Conda Environment script finished successfully." >&2
  else
    echo "❌ Conda Environment script exited with error ${_rc}." >&2
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT

__usage__() {
  cat << 'EOF'
Usage: install.bash [OPTIONS]

Options:
  --conda_dir <value>                             Path to the conda installation directory.
  --env_files <value>  (repeatable)               Paths to conda environment YAML files to create or update.
  --env_dirs <value>  (repeatable)                Paths to directories to scan for conda environment YAML files.
  --env_name <value>                              Name of a conda environment to create or update from inline package options.
  --packages <value>                              Space-separated list of conda packages to install into the environment
  --python_version <value>                        Python version to use when creating the inline environment specified by 'env_name'.
  --channels <value>  (repeatable)                Conda channels to add to the configuration.
  --strict_channel_priority {true,false}          Set channel_priority to strict in the conda configuration. (default: "false")
  --pip_requirements_files <value>  (repeatable)  Paths to pip requirements files to install.
  --pip_env <value>                               Name of the conda environment to pip-install requirements into.
  --post_env_script <value>                       Path to a script to run after each environment is created or updated.
  --solver <value>                                Conda solver to use. 'auto' prefers mamba if available, falls back to conda. (default: "auto")
  --keep_cache {true,false}                       Skip running 'conda clean' after all environments are set up. (default: "false")
  --debug {true,false}                            Enable debug output. This adds `set -x` to the installer script, which prints each command before executing it. (default: "false")
  --logfile <value>                               Log all output (stdout + stderr) to this file in addition to console.
  -h, --help                                      Show this help
EOF
  return
}

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  CONDA_DIR=""
  ENV_FILES=()
  ENV_DIRS=()
  ENV_NAME=""
  PACKAGES=""
  PYTHON_VERSION=""
  CHANNELS=()
  STRICT_CHANNEL_PRIORITY=false
  PIP_REQUIREMENTS_FILES=()
  PIP_ENV=""
  POST_ENV_SCRIPT=""
  SOLVER="auto"
  KEEP_CACHE=false
  DEBUG=false
  LOGFILE=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --conda_dir)
        shift
        CONDA_DIR="$1"
        echo "📩 Read argument 'conda_dir': '${CONDA_DIR}'" >&2
        shift
        ;;
      --env_files)
        shift
        ENV_FILES+=("$1")
        echo "📩 Read argument 'env_files': '$1'" >&2
        shift
        ;;
      --env_dirs)
        shift
        ENV_DIRS+=("$1")
        echo "📩 Read argument 'env_dirs': '$1'" >&2
        shift
        ;;
      --env_name)
        shift
        ENV_NAME="$1"
        echo "📩 Read argument 'env_name': '${ENV_NAME}'" >&2
        shift
        ;;
      --packages)
        shift
        PACKAGES="$1"
        echo "📩 Read argument 'packages': '${PACKAGES}'" >&2
        shift
        ;;
      --python_version)
        shift
        PYTHON_VERSION="$1"
        echo "📩 Read argument 'python_version': '${PYTHON_VERSION}'" >&2
        shift
        ;;
      --channels)
        shift
        CHANNELS+=("$1")
        echo "📩 Read argument 'channels': '$1'" >&2
        shift
        ;;
      --strict_channel_priority)
        shift
        STRICT_CHANNEL_PRIORITY="$1"
        echo "📩 Read argument 'strict_channel_priority': '${STRICT_CHANNEL_PRIORITY}'" >&2
        shift
        ;;
      --pip_requirements_files)
        shift
        PIP_REQUIREMENTS_FILES+=("$1")
        echo "📩 Read argument 'pip_requirements_files': '$1'" >&2
        shift
        ;;
      --pip_env)
        shift
        PIP_ENV="$1"
        echo "📩 Read argument 'pip_env': '${PIP_ENV}'" >&2
        shift
        ;;
      --post_env_script)
        shift
        POST_ENV_SCRIPT="$1"
        echo "📩 Read argument 'post_env_script': '${POST_ENV_SCRIPT}'" >&2
        shift
        ;;
      --solver)
        shift
        SOLVER="$1"
        echo "📩 Read argument 'solver': '${SOLVER}'" >&2
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
  [ "${CONDA_DIR+defined}" ] && echo "📩 Read argument 'conda_dir': '${CONDA_DIR}'" >&2
  if [ "${ENV_FILES+defined}" ]; then
    if [ -n "${ENV_FILES-}" ]; then
      mapfile -t ENV_FILES < <(printf '%s\n' "${ENV_FILES}" | grep -v '^$')
      for _item in "${ENV_FILES[@]}"; do
        echo "📩 Read argument 'env_files': '$_item'" >&2
      done
    else
      ENV_FILES=()
    fi
  fi
  if [ "${ENV_DIRS+defined}" ]; then
    if [ -n "${ENV_DIRS-}" ]; then
      mapfile -t ENV_DIRS < <(printf '%s\n' "${ENV_DIRS}" | grep -v '^$')
      for _item in "${ENV_DIRS[@]}"; do
        echo "📩 Read argument 'env_dirs': '$_item'" >&2
      done
    else
      ENV_DIRS=()
    fi
  fi
  [ "${ENV_NAME+defined}" ] && echo "📩 Read argument 'env_name': '${ENV_NAME}'" >&2
  [ "${PACKAGES+defined}" ] && echo "📩 Read argument 'packages': '${PACKAGES}'" >&2
  [ "${PYTHON_VERSION+defined}" ] && echo "📩 Read argument 'python_version': '${PYTHON_VERSION}'" >&2
  if [ "${CHANNELS+defined}" ]; then
    if [ -n "${CHANNELS-}" ]; then
      mapfile -t CHANNELS < <(printf '%s\n' "${CHANNELS}" | grep -v '^$')
      for _item in "${CHANNELS[@]}"; do
        echo "📩 Read argument 'channels': '$_item'" >&2
      done
    else
      CHANNELS=()
    fi
  fi
  [ "${STRICT_CHANNEL_PRIORITY+defined}" ] && echo "📩 Read argument 'strict_channel_priority': '${STRICT_CHANNEL_PRIORITY}'" >&2
  if [ "${PIP_REQUIREMENTS_FILES+defined}" ]; then
    if [ -n "${PIP_REQUIREMENTS_FILES-}" ]; then
      mapfile -t PIP_REQUIREMENTS_FILES < <(printf '%s\n' "${PIP_REQUIREMENTS_FILES}" | grep -v '^$')
      for _item in "${PIP_REQUIREMENTS_FILES[@]}"; do
        echo "📩 Read argument 'pip_requirements_files': '$_item'" >&2
      done
    else
      PIP_REQUIREMENTS_FILES=()
    fi
  fi
  [ "${PIP_ENV+defined}" ] && echo "📩 Read argument 'pip_env': '${PIP_ENV}'" >&2
  [ "${POST_ENV_SCRIPT+defined}" ] && echo "📩 Read argument 'post_env_script': '${POST_ENV_SCRIPT}'" >&2
  [ "${SOLVER+defined}" ] && echo "📩 Read argument 'solver': '${SOLVER}'" >&2
  [ "${KEEP_CACHE+defined}" ] && echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${CONDA_DIR+defined}" ] || {
  CONDA_DIR=""
  echo "ℹ️ Argument 'conda_dir' set to default value ''." >&2
}
[ "${ENV_FILES+defined}" ] || {
  ENV_FILES=()
  echo "ℹ️ Argument 'env_files' set to default value '(empty)'." >&2
}
[ "${ENV_DIRS+defined}" ] || {
  ENV_DIRS=()
  echo "ℹ️ Argument 'env_dirs' set to default value '(empty)'." >&2
}
[ "${ENV_NAME+defined}" ] || {
  ENV_NAME=""
  echo "ℹ️ Argument 'env_name' set to default value ''." >&2
}
[ "${PACKAGES+defined}" ] || {
  PACKAGES=""
  echo "ℹ️ Argument 'packages' set to default value ''." >&2
}
[ "${PYTHON_VERSION+defined}" ] || {
  PYTHON_VERSION=""
  echo "ℹ️ Argument 'python_version' set to default value ''." >&2
}
[ "${CHANNELS+defined}" ] || {
  CHANNELS=()
  echo "ℹ️ Argument 'channels' set to default value '(empty)'." >&2
}
[ "${STRICT_CHANNEL_PRIORITY+defined}" ] || {
  STRICT_CHANNEL_PRIORITY=false
  echo "ℹ️ Argument 'strict_channel_priority' set to default value 'false'." >&2
}
[ "${PIP_REQUIREMENTS_FILES+defined}" ] || {
  PIP_REQUIREMENTS_FILES=()
  echo "ℹ️ Argument 'pip_requirements_files' set to default value '(empty)'." >&2
}
[ "${PIP_ENV+defined}" ] || {
  PIP_ENV=""
  echo "ℹ️ Argument 'pip_env' set to default value ''." >&2
}
[ "${POST_ENV_SCRIPT+defined}" ] || {
  POST_ENV_SCRIPT=""
  echo "ℹ️ Argument 'post_env_script' set to default value ''." >&2
}
[ "${SOLVER+defined}" ] || {
  SOLVER="auto"
  echo "ℹ️ Argument 'solver' set to default value 'auto'." >&2
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

# END OF AUTOGENERATED BLOCK

for elem in "${ENV_DIRS[@]}"; do
  [ -n "${elem-}" ] && [ ! -d "${elem}" ] && {
    echo "⛔ Directory argument to parameter 'env_dirs' not found: '${elem}'" >&2
    exit 1
  }
done
for elem in "${ENV_FILES[@]}"; do
  [ -n "${elem-}" ] && [ ! -f "${elem}" ] && {
    echo "⛔ File argument to parameter 'env_files' not found: '${elem}'" >&2
    exit 1
  }
done
for elem in "${PIP_REQUIREMENTS_FILES[@]}"; do
  [ -n "${elem-}" ] && [ ! -f "${elem}" ] && {
    echo "⛔ File argument to parameter 'pip_requirements_files' not found: '${elem}'" >&2
    exit 1
  }
done
if [[ -n "$ENV_NAME" ]] && [[ -z "$PACKAGES" ]] && [[ -z "$PYTHON_VERSION" ]]; then
  echo "⛔ 'env_name' requires at least one of 'packages' or 'python_version' to be set." >&2
  exit 1
fi

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

discover_conda
resolve_solver
apply_channels
if [[ -n "$ENV_NAME" ]]; then setup_inline_env; fi
if [[ ${#ENV_FILES[@]} -gt 0 || ${#ENV_DIRS[@]} -gt 0 ]]; then setup_environment; fi
if [[ "$KEEP_CACHE" == false ]]; then
  echo "🧹 Cleaning up conda cache." >&2
  "$SOLVER_EXEC" clean --all -y
fi
