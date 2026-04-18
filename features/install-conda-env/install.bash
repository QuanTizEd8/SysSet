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
