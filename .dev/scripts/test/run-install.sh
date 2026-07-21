#!/usr/bin/env bash
# .dev/scripts/test/run-install.sh — runner for install framework bats tests.
#
# Usage:
#   bash .dev/scripts/test/run-install.sh                  # all modules
#   bash .dev/scripts/test/run-install.sh --module dep_install
#   bash .dev/scripts/test/run-install.sh --filter "dep_"
#   bash .dev/scripts/test/run-install.sh --jobs 1

set -euo pipefail

if ((BASH_VERSINFO[0] < 4)); then
  for _try_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_try_bash" ]] && "$_try_bash" -c '(( BASH_VERSINFO[0] >= 4 ))' 2> /dev/null; then
      exec "$_try_bash" "$0" "$@"
    fi
  done
  printf '⛔ bash ≥4.0 required (found %s). Install via: brew install bash\n' \
    "$BASH_VERSION" >&2
  exit 1
fi

export PATH
PATH="$(dirname "$BASH"):$PATH"

if [[ -n "${REPO_ROOT:-}" ]]; then
  _REPO_ROOT="$REPO_ROOT"
else
  _REPO_ROOT="$(git -C "$(cd "$(dirname "$0")" && pwd)" rev-parse --show-toplevel)"
fi
export REPO_ROOT="$_REPO_ROOT"
_BATS="${_REPO_ROOT}/test/lib/bats/bats-core/bin/bats"
_INSTALL_DIR="${_REPO_ROOT}/test/install"

_module=""
_filter=""
_jobs=0
_clean_path=false
declare -a _paths=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --module)
      shift
      _module="$1"
      shift
      ;;
    --filter)
      shift
      _filter="$1"
      shift
      ;;
    --jobs)
      shift
      _jobs="$1"
      shift
      ;;
    --paths)
      shift
      _paths+=("$1")
      shift
      ;;
    --clean-path)
      _clean_path=true
      shift
      ;;
    --help | -h)
      cat << 'HELP'
Usage: bash .dev/scripts/test/run-install.sh [--module <name>] [--filter <regex>] [--jobs <n>] [--paths <glob>]

  --module <name>    Run only test/install/<name>.bats
  --filter <regex>   Pass --filter to bats (matches test names by regex)
  --jobs <n>         Parallel job count (default: auto)
  --paths <glob>     Add explicit test file/path glob (repeatable)
  --clean-path       Restrict PATH to system baseline (macOS isolation)
HELP
      exit 0
      ;;
    *)
      echo "⛔ Unknown option: '$1'" >&2
      exit 1
      ;;
  esac
done

if [[ "$_clean_path" == true ]]; then
  PATH="$(dirname "$BASH"):/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH
fi

if [[ ! -x "$_BATS" ]]; then
  echo "⛔ bats not found at '${_BATS}'." >&2
  echo "   Run: git submodule update --init --recursive" >&2
  exit 1
fi

_fixture="${REPO_ROOT}/src/install-jq/install.bash"
if [[ ! -f "$_fixture" ]]; then
  echo "⛔ Synced install.bash fixture missing at '${_fixture}'." >&2
  echo "   Run: just sync-src" >&2
  exit 1
fi

declare -a _test_files=()
if [[ ${#_paths[@]} -gt 0 ]]; then
  for _path_glob in "${_paths[@]}"; do
    while IFS= read -r -d '' _f; do
      _test_files+=("$_f")
    done < <(compgen -G "${_path_glob}" | while IFS= read -r _m; do
      [[ -d "$_m" ]] && find "$_m" -name '*.bats' -print0 || printf '%s\0' "$_m"
    done)
  done
elif [[ -n "$_module" ]]; then
  _target="${_INSTALL_DIR}/${_module}.bats"
  if [[ ! -f "$_target" ]]; then
    echo "⛔ Install framework test not found: '${_target}'" >&2
    exit 1
  fi
  _test_files=("$_target")
else
  while IFS= read -r -d '' _f; do
    _test_files+=("$_f")
  done < <(find "$_INSTALL_DIR" -maxdepth 1 -name '*.bats' -print0 | sort -z)
fi

if [[ ${#_test_files[@]} -eq 0 ]]; then
  echo "⚠️  No .bats files found in '${_INSTALL_DIR}'." >&2
  exit 0
fi

# Install-framework tests are an ordinary (non-bootstrap) BATS suite and need
# only jq/yq. Container scenarios may provide immutable prepared binaries;
# local runs resolve the same tools from PATH in setup_suite.bash.
case "${DEVFEATS_TEST_TOOL_CACHE:-}" in
  '' | required) DEVFEATS_TEST_TOOL_CACHE=required ;;
  *)
    echo "⛔ Install framework tests require DEVFEATS_TEST_TOOL_CACHE=required." >&2
    exit 2
    ;;
esac
DEVFEATS_TEST_REQUIRED_TOOLS="jq yq"
export DEVFEATS_TEST_TOOL_CACHE DEVFEATS_TEST_REQUIRED_TOOLS

declare -a _bats_args=(--print-output-on-failure)
[[ "$_jobs" -gt 0 ]] && _bats_args+=(--jobs "$_jobs")
[[ -n "$_filter" ]] && _bats_args+=(--filter "$_filter")

exec "$BASH" "$_BATS" "${_bats_args[@]}" "${_test_files[@]}"
