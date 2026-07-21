#!/usr/bin/env bash
# .dev/scripts/test/run-unit.sh — local runner for lib/ unit tests.
#
# Usage:
#   bash .dev/scripts/test/run-unit.sh                       # run lean tests
#   bash .dev/scripts/test/run-unit.sh --module os           # run test/lib/os.bats only
#   bash .dev/scripts/test/run-unit.sh --tier integration    # integration tests only
#   bash .dev/scripts/test/run-unit.sh --tier all            # lean + integration
#   bash .dev/scripts/test/run-unit.sh --filter "platform"   # test-name regex
#   bash .dev/scripts/test/run-unit.sh --jobs 1              # serial execution (default)

set -euo pipefail

# macOS ships bash 3.2; re-exec with bash ≥4 if needed.
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

# Ensure 'env bash' resolves to the same bash ≥4 we re-exec'd with.
# bats forks sub-scripts (bats-exec-test, bats-exec-suite, …) via their
# #!/usr/bin/env bash shebang; without this, those pick up /bin/bash 3.2.
export PATH
PATH="$(dirname "$BASH"):$PATH"

if [[ -n "${REPO_ROOT:-}" ]]; then
  _REPO_ROOT="$REPO_ROOT"
else
  _REPO_ROOT="$(git -C "$(cd "$(dirname "$0")" && pwd)" rev-parse --show-toplevel)"
fi
_REPO_ROOT="$(cd "$_REPO_ROOT" && pwd -P)"
export REPO_ROOT="$_REPO_ROOT"
_BATS="${_REPO_ROOT}/test/lib/bats/bats-core/bin/bats"
_UNIT_DIR="${_REPO_ROOT}/test/lib"

# ── Argument parsing ─────────────────────────────────────────────────────────
_module=""
_filter=""
_jobs=1
_tier="lean"
_tier_explicit=false
_list_files=false
_clean_path=false
_path_prepend=""
declare -a _paths=()

_usage_error() {
  printf '⛔ %s\n' "$1" >&2
  printf 'Run with --help for usage.\n' >&2
  exit 2
}

_infra_error() {
  printf '⛔ Test runner infrastructure failure: %s\n' "$1" >&2
  exit 1
}

_require_value() {
  [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || _usage_error "Option '$1' requires a value."
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --module)
      _require_value "$@"
      shift
      _module="$1"
      shift
      ;;
    --filter)
      _require_value "$@"
      shift
      _filter="$1"
      shift
      ;;
    --filter=*)
      _filter="${1#--filter=}"
      [[ -n "$_filter" ]] || _usage_error "Option '--filter' requires a value."
      shift
      ;;
    --jobs)
      _require_value "$@"
      shift
      _jobs="$1"
      shift
      ;;
    --path)
      _require_value "$@"
      shift
      _paths+=("$1")
      shift
      ;;
    --tier)
      _require_value "$@"
      shift
      _tier="$1"
      _tier_explicit=true
      shift
      ;;
    --list-files)
      _list_files=true
      shift
      ;;
    --clean-path)
      _clean_path=true
      shift
      ;;
    --path-prepend)
      _require_value "$@"
      shift
      _path_prepend="$1"
      shift
      ;;
    --help | -h)
      cat << 'HELP'
Usage: bash .dev/scripts/test/run-unit.sh [--tier lean|integration|all] [--module <name>] [--path <file>] [--filter <regex>|--filter=<regex>] [--jobs <n>] [--list-files] [--clean-path] [--path-prepend <dirs>]

  --tier <tier>         Select lean, integration, or all tests (default: lean)
  --module <name>       Filter the selected tier to one module
  --path <file>         Run one exact .bats file (repeatable; bypasses tiers)
  --filter <regex>      Pass a test-name regex to BATS; use --filter= for values beginning --
  --jobs <n>            BATS parallel job count, 1..256 (default: 1, serial)
  --list-files          Print selected repository-relative files and exit
  --clean-path          Strip PATH to system baseline (macOS)
  --path-prepend <dirs> Prepend colon-separated dirs to PATH after --clean-path
HELP
      exit 0
      ;;
    *)
      echo "⛔ Unknown option: '$1'" >&2
      exit 2
      ;;
  esac
done

case "$_tier" in
  lean | integration | all) ;;
  *) _usage_error "Invalid tier '${_tier}'; expected lean, integration, or all." ;;
esac
[[ "$_jobs" =~ ^[1-9][0-9]*$ ]] || _usage_error "Invalid --jobs value '${_jobs}'; expected an integer from 1 to 256."
if [[ ${#_jobs} -gt 3 ]]; then
  _usage_error "Invalid --jobs value '${_jobs}'; expected an integer from 1 to 256."
fi
_jobs_num=$((10#$_jobs))
if [[ $_jobs_num -gt 256 ]]; then
  _usage_error "Invalid --jobs value '${_jobs}'; expected an integer from 1 to 256."
fi
if [[ -n "$_module" && ! "$_module" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  _usage_error "Invalid module name '${_module}'."
fi
if [[ ${#_paths[@]} -gt 0 && "$_tier_explicit" == true ]]; then
  _usage_error "--path and --tier are mutually exclusive."
fi
if [[ ${#_paths[@]} -gt 0 && -n "$_module" ]]; then
  _usage_error "--path and --module are mutually exclusive."
fi

# ── PATH isolation ───────────────────────────────────────────────────────────
# Strips the GHA runner's pre-installed tools, keeping only the macOS system
# baseline plus the bash ≥4 binary selected by the re-exec above.
if [[ "$_clean_path" == true ]]; then
  PATH="$(dirname "$BASH"):/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH
fi
if [[ -n "$_path_prepend" ]]; then
  PATH="${_path_prepend}:${PATH}"
  export PATH
fi

# ── Pre-flight checks ────────────────────────────────────────────────────────
# ── Build file list ──────────────────────────────────────────────────────────
_selection_raw=""
_selection_sorted=""
_tap_log=""
_cleanup_runner_files() {
  [[ -z "$_selection_raw" ]] || rm -f -- "$_selection_raw"
  [[ -z "$_selection_sorted" ]] || rm -f -- "$_selection_sorted"
  [[ -z "$_tap_log" ]] || rm -f -- "$_tap_log"
}
trap _cleanup_runner_files EXIT

_selection_raw="$(mktemp)" || _infra_error "could not create the selection staging file"
_selection_sorted="$(mktemp)" || _infra_error "could not create the sorted selection file"
if [[ ${#_paths[@]} -gt 0 ]]; then
  for _path in "${_paths[@]}"; do
    [[ "$_path" == *.bats ]] || _usage_error "Explicit path must end in .bats: '${_path}'."
    [[ -e "$_path" ]] || _usage_error "Test file does not exist: '${_path}'."
    [[ ! -L "$_path" ]] || _usage_error "Symlink test paths are not allowed: '${_path}'."
    [[ -f "$_path" ]] || _usage_error "Test path is not a regular file: '${_path}'."
    _path_dir="$(cd "$(dirname "$_path")" && pwd -P)" || _usage_error "Cannot resolve test path: '${_path}'."
    _canonical_path="${_path_dir}/$(basename "$_path")"
    case "$_path_dir" in
      "${_UNIT_DIR}/bats" | "${_UNIT_DIR}/bats"/*)
        _usage_error "Vendored BATS tests cannot be selected: '${_path}'."
        ;;
      "$_UNIT_DIR" | "${_UNIT_DIR}/integration" | "${_UNIT_DIR}/bootstrap") ;;
      *) _usage_error "Test path must be directly beneath test/lib, test/lib/integration, or test/lib/bootstrap: '${_path}'." ;;
    esac
    printf '%s\0' "$_canonical_path" >> "$_selection_raw" || _infra_error "could not stage an explicit test path"
  done
elif [[ -n "$_module" ]]; then
  if [[ "$_tier" == lean || "$_tier" == all ]]; then
    _target="${_UNIT_DIR}/${_module}.bats"
    if [[ ! -L "$_target" && -f "$_target" ]]; then
      printf '%s\0' "$_target" >> "$_selection_raw" || _infra_error "could not stage the lean module test"
    fi
  fi
  if [[ "$_tier" == integration || "$_tier" == all ]]; then
    _target="${_UNIT_DIR}/integration/${_module}.bats"
    if [[ ! -L "$_target" && -f "$_target" ]]; then
      printf '%s\0' "$_target" >> "$_selection_raw" || _infra_error "could not stage the integration module test"
    fi
  fi
else
  if [[ "$_tier" == lean || "$_tier" == all ]]; then
    if ! find "$_UNIT_DIR" -maxdepth 1 -type f -name '*.bats' -print0 >> "$_selection_raw"; then
      _infra_error "find failed while selecting lean tests"
    fi
  fi
  if [[ "$_tier" == integration || "$_tier" == all ]]; then
    if ! find "$_UNIT_DIR/integration" -maxdepth 1 -type f -name '*.bats' -print0 >> "$_selection_raw"; then
      _infra_error "find failed while selecting integration tests"
    fi
  fi
fi

if [[ ! -s "$_selection_raw" ]]; then
  _usage_error "No tests matched the requested selection."
fi

# Canonical, deterministic, duplicate-free order for every selection mode.
if ! LC_ALL=C sort -zu "$_selection_raw" > "$_selection_sorted"; then
  _infra_error "sort failed while ordering selected tests"
fi
declare -a _test_files=()
while IFS= read -r -d '' _f; do
  _test_files+=("$_f")
done < "$_selection_sorted"
if [[ ${#_test_files[@]} -eq 0 ]]; then
  _infra_error "sorting produced an empty test selection"
fi

# Derive the workload before invoking BATS. Dedicated bootstrap tests must run
# without the prepared ordinary-suite cache and may not be mixed with ordinary
# files in one BATS process.
_has_ordinary=false
_has_bootstrap=false
_needs_jsonschema=false
_needs_oras=false
for _f in "${_test_files[@]}"; do
  case "$_f" in
    "${_UNIT_DIR}/bootstrap/"*) _has_bootstrap=true ;;
    *) _has_ordinary=true ;;
  esac
  [[ "$_f" == "${_UNIT_DIR}/integration/json.bats" ]] && _needs_jsonschema=true
  [[ "$_f" == "${_UNIT_DIR}/integration/oci.bats" ]] && _needs_oras=true
done
if [[ "$_has_ordinary" == true && "$_has_bootstrap" == true ]]; then
  _usage_error "Ordinary and bootstrap test files cannot be selected in the same run."
fi

_requested_tool_cache="${DEVFEATS_TEST_TOOL_CACHE:-}"
if [[ "$_has_bootstrap" == true ]]; then
  [[ $_jobs_num -eq 1 ]] ||
    _usage_error "Bootstrap tests must run serially; --jobs must be 1."
  [[ -z "$_requested_tool_cache" || "$_requested_tool_cache" == disabled ]] ||
    _usage_error "Bootstrap tests require DEVFEATS_TEST_TOOL_CACHE=disabled."
  [[ -z "${DEVFEATS_TEST_TOOL_SOURCE_DIR:-}" ]] ||
    _usage_error "Bootstrap tests must not receive DEVFEATS_TEST_TOOL_SOURCE_DIR."
  DEVFEATS_TEST_TOOL_CACHE=disabled
  DEVFEATS_TEST_REQUIRED_TOOLS=""
else
  [[ -z "$_requested_tool_cache" || "$_requested_tool_cache" == required ]] ||
    _usage_error "Ordinary tests require DEVFEATS_TEST_TOOL_CACHE=required."
  DEVFEATS_TEST_TOOL_CACHE=required
  DEVFEATS_TEST_REQUIRED_TOOLS="jq yq"
  [[ "$_needs_jsonschema" == true ]] && DEVFEATS_TEST_REQUIRED_TOOLS+=" jsonschema"
  [[ "$_needs_oras" == true ]] && DEVFEATS_TEST_REQUIRED_TOOLS+=" oras"
fi
export DEVFEATS_TEST_TOOL_CACHE DEVFEATS_TEST_REQUIRED_TOOLS

if [[ "$_list_files" == true ]]; then
  for _f in "${_test_files[@]}"; do
    printf '%s\n' "${_f#"${_REPO_ROOT}/"}"
  done
  exit 0
fi

if [[ ! -x "$_BATS" ]]; then
  echo "⛔ bats not found at '${_BATS}'." >&2
  echo "   Run: git submodule update --init --recursive" >&2
  exit 1
fi

if [[ $_jobs_num -gt 1 ]] && ! command -v flock > /dev/null 2>&1 && ! command -v shlock > /dev/null 2>&1; then
  _infra_error "parallel tests require flock or shlock on PATH; install util-linux on Linux or 'brew install flock' on macOS, or use --jobs 1"
fi

# ── Run ──────────────────────────────────────────────────────────────────────
# Force tap: bats' own summary (the `pretty` formatter) needs a real TTY and
# relies on cursor-repositioning escape codes that only render correctly when
# interpreted live by a terminal — once `just capture` strips ANSI for the
# plain-text log file, those codes leave overlapping/garbled lines instead of
# a summary. Plain `tap` (bats' own fallback without a TTY) has no summary at
# all by TAP protocol design — summarizing is meant to be the consumer's job.
# So: always request tap (deterministic regardless of TTY), tee it to a temp
# file, and print our own summary from it below.
declare -a _bats_args=(
  --print-output-on-failure
  --formatter tap
  --setup-suite-file "${_UNIT_DIR}/setup_suite.bash"
)

[[ $_jobs_num -gt 1 ]] && _bats_args+=(--jobs "$_jobs" --no-parallelize-across-files)
[[ -n "$_filter" ]] && _bats_args+=(--filter "$_filter")

_tap_log="$(mktemp)" || _infra_error "could not create the TAP staging file"
[[ -n "$_tap_log" ]] || _infra_error "could not create the TAP staging file"

# Invoke bats via the same bash ≥4 binary we re-exec'd with, so bats and all
# test files run under bash ≥4 regardless of what `env bash` resolves to.
# `set +e` (not `pipeline || true`) around the pipeline: appending `|| true`
# directly to the pipe runs `true` as its own trailing pipeline on failure,
# which overwrites PIPESTATUS with `true`'s own (0) before we can read it.
set +e
"$BASH" "$_BATS" "${_bats_args[@]}" "${_test_files[@]}" | tee "$_tap_log"
_pipeline_status=("${PIPESTATUS[@]}")
set -e
_bats_rc=${_pipeline_status[0]}
_tee_rc=${_pipeline_status[1]}
_run_rc=$_bats_rc
if [[ $_bats_rc -eq 0 && $_tee_rc -ne 0 ]]; then
  printf '⛔ Test runner infrastructure failure: tee exited with status %s.\n' "$_tee_rc" >&2
  _run_rc=$_tee_rc
fi

_planned_total=""
_tap_plan_count=0
_tap_plan_position=""
_tap_version_seen=false
_tap_bailed_out=false
_tap_result_line_seen=false
_tap_middle_plan_reported=false
declare -a _tap_errors=()
declare -a _tap_result_ids=()
declare -A _tap_result_kinds=()
declare -A _tap_result_names=()
_tap_plan_re='^1\.\.([0-9]+)([[:space:]]+(.*))?$'
_tap_plan_skip_re='^#[[:space:]]*([Ss][Kk][Ii][Pp]([[:space:]]+.*)?|[Ss][Kk][Ii][Pp][Pp][Ee][Dd]:([[:space:]]*.*)?)$'
_tap_result_re='^(ok|not ok)[[:space:]]+([0-9]+)([[:space:]]+(.*))?$'
_tap_bailout_re='^Bail[[:space:]]out!([[:space:]].*)?$'
_tap_directive_re='^(.*)[[:space:]]#[[:space:]]*([Ss][Kk][Ii][Pp]|[Tt][Oo][Dd][Oo])([[:space:]]+.*)?$'
_tap_skip_marker_re='(^|[[:space:]])#[[:space:]]*[Ss][Kk][Ii][Pp]([[:space:]]|$)'
_tap_todo_marker_re='(^|[[:space:]])#[[:space:]]*[Tt][Oo][Dd][Oo]([[:space:]]|$)'

_tap_error() {
  _tap_errors+=("$1")
}

# Normalize without evaluating untrusted text as arithmetic. Nine decimal
# digits fit safely even on platforms whose shell integer is only 32 bits;
# wider inputs are protocol errors rather than arithmetic expressions.
_normalize_tap_uint() {
  local _raw_uint=$1
  [[ "$_raw_uint" =~ ^[0-9]+$ && ${#_raw_uint} -le 9 ]] || return 1
  while [[ ${#_raw_uint} -gt 1 && "${_raw_uint:0:1}" == 0 ]]; do
    _raw_uint="${_raw_uint:1}"
  done
  _normalized_tap_uint="$_raw_uint"
}

# Parse only top-level TAP. Blank lines, comments, and indented diagnostics are
# intentionally opaque. Everything else at column zero must be protocol that
# we understand; silently ignoring it could turn truncated or corrupt TAP into
# a false-green summary.
while IFS= read -r _tap_line || [[ -n "$_tap_line" ]]; do
  if [[ "$_tap_bailed_out" == true ]]; then
    continue
  fi
  if [[ "$_tap_line" =~ $_tap_bailout_re ]]; then
    _tap_bailed_out=true
    _tap_error "Bail out! was reported"
    continue
  fi
  if [[ -z "$_tap_line" || "$_tap_line" == [[:space:]]* || "$_tap_line" == \#* ]]; then
    continue
  fi
  if [[ "$_tap_line" == "TAP version 13" ]]; then
    if [[ "$_tap_version_seen" == true || $_tap_plan_count -gt 0 || "$_tap_result_line_seen" == true ]]; then
      _tap_error "TAP version header is duplicated or misplaced"
    fi
    _tap_version_seen=true
    continue
  fi
  if [[ "$_tap_line" =~ $_tap_plan_re ]]; then
    ((_tap_plan_count += 1))
    _candidate_plan="${BASH_REMATCH[1]}"
    _candidate_plan_suffix="${BASH_REMATCH[3]:-}"
    if ! _normalize_tap_uint "$_candidate_plan"; then
      _tap_error "TAP plan has an unsupported numeric total: ${_candidate_plan}"
      continue
    fi
    if ((_tap_plan_count > 1)); then
      if [[ -n "$_planned_total" && "$_planned_total" != "$_normalized_tap_uint" ]]; then
        _tap_error "TAP contains conflicting plans"
      else
        _tap_error "TAP contains duplicate plans"
      fi
      continue
    fi
    _planned_total="$_normalized_tap_uint"
    if [[ -n "$_candidate_plan_suffix" ]]; then
      if [[ ! "$_candidate_plan_suffix" =~ $_tap_plan_skip_re ]]; then
        _tap_error "TAP plan has an unsupported directive: ${_candidate_plan_suffix}"
      elif [[ "$_planned_total" != 0 ]]; then
        _tap_error "TAP skip-all directive requires a zero-test plan"
      fi
    fi
    if [[ "$_tap_result_line_seen" == true ]]; then
      _tap_plan_position="after"
    else
      _tap_plan_position="before"
    fi
    continue
  fi
  if [[ "$_tap_line" =~ $_tap_result_re ]]; then
    if [[ "$_tap_plan_position" == "after" && "$_tap_middle_plan_reported" == false ]]; then
      _tap_error "TAP plan appears between result lines"
      _tap_middle_plan_reported=true
    fi
    _tap_result_line_seen=true
    _tap_status="${BASH_REMATCH[1]}"
    _tap_number_raw="${BASH_REMATCH[2]}"
    _tap_name="${BASH_REMATCH[4]:-}"
    if ! _normalize_tap_uint "$_tap_number_raw" || [[ "$_normalized_tap_uint" == 0 ]]; then
      _tap_error "TAP result has an unsupported test number: ${_tap_number_raw}"
      continue
    fi
    _tap_number="$_normalized_tap_uint"
    if [[ -n "${_tap_result_kinds[$_tap_number]+present}" ]]; then
      _tap_error "TAP result number ${_tap_number} is duplicated"
      continue
    fi

    _tap_kind="passed"
    [[ "$_tap_status" == "not ok" ]] && _tap_kind="failed"
    _tap_display_name="$_tap_name"
    _tap_directive_subject=" ${_tap_name}"
    if [[ "$_tap_directive_subject" =~ $_tap_directive_re ]]; then
      _tap_display_name="${BASH_REMATCH[1]:1}"
      _tap_directive="${BASH_REMATCH[2]}"
      while [[ "$_tap_display_name" == *[[:space:]] ]]; do
        _tap_display_name="${_tap_display_name%?}"
      done
      _tap_prefix_has_skip=false
      _tap_prefix_has_todo=false
      [[ "$_tap_display_name" =~ $_tap_skip_marker_re ]] && _tap_prefix_has_skip=true
      [[ "$_tap_display_name" =~ $_tap_todo_marker_re ]] && _tap_prefix_has_todo=true
      case "$_tap_directive" in
        [Ss][Kk][Ii][Pp])
          _tap_kind="skipped"
          if [[ "$_tap_prefix_has_todo" == true ]]; then
            _tap_error "TAP result ${_tap_number} has conflicting SKIP and TODO directives"
          elif [[ "$_tap_prefix_has_skip" == true ]]; then
            _tap_error "TAP result ${_tap_number} has multiple SKIP directives"
          fi
          ;;
        [Tt][Oo][Dd][Oo])
          _tap_kind="todo"
          if [[ "$_tap_prefix_has_skip" == true ]]; then
            _tap_error "TAP result ${_tap_number} has conflicting SKIP and TODO directives"
          elif [[ "$_tap_prefix_has_todo" == true ]]; then
            _tap_error "TAP result ${_tap_number} has multiple TODO directives"
          fi
          ;;
      esac
    fi

    _tap_result_ids+=("$_tap_number")
    _tap_result_kinds["$_tap_number"]="$_tap_kind"
    _tap_result_names["$_tap_number"]="$_tap_display_name"
    continue
  fi
  _tap_error "unrecognized top-level TAP: ${_tap_line}"
done < "$_tap_log"

if ((_tap_plan_count == 0)); then
  _tap_error "TAP plan is missing"
elif [[ -z "$_planned_total" ]]; then
  _tap_error "TAP plan is invalid"
fi

_completed_count=0
_passed_count=0
_failed_count=0
_skipped_count=0
_todo_count=0
declare -a _failed_names=()
for _tap_number in "${_tap_result_ids[@]}"; do
  if [[ -n "$_planned_total" ]] && ((_tap_number > _planned_total)); then
    _tap_error "TAP result number ${_tap_number} is outside plan 1..${_planned_total}"
    continue
  fi
  ((_completed_count += 1))
  case "${_tap_result_kinds[$_tap_number]}" in
    passed) ((_passed_count += 1)) ;;
    failed)
      ((_failed_count += 1))
      _failed_name="${_tap_result_names[$_tap_number]}"
      [[ -n "$_failed_name" ]] || _failed_name="test ${_tap_number}"
      _failed_names+=("$_failed_name")
      ;;
    skipped) ((_skipped_count += 1)) ;;
    todo) ((_todo_count += 1)) ;;
  esac
done

_incomplete_count=0
if [[ -n "$_planned_total" ]] && ((_planned_total > _completed_count)); then
  _incomplete_count=$((_planned_total - _completed_count))
  _tap_error "TAP is missing ${_incomplete_count} planned result(s)"
fi
if [[ ${#_tap_errors[@]} -gt 0 ]]; then
  printf '⛔ Test runner infrastructure failure: invalid TAP output:\n' >&2
  printf '  - %s\n' "${_tap_errors[@]}" >&2
  if [[ $_run_rc -eq 0 ]]; then
    _run_rc=1
  fi
fi
if [[ $_bats_rc -eq 0 && $_failed_count -gt 0 ]]; then
  printf '⛔ Test runner infrastructure failure: BATS exited with status 0 but TAP reported %s failed test(s).\n' \
    "$_failed_count" >&2
  if [[ $_run_rc -eq 0 ]]; then
    _run_rc=1
  fi
fi

echo
if [[ -n "$_planned_total" ]]; then
  printf '── Summary: %s/%s completed, %s passed, %s failed, %s skipped, %s TODO, %s incomplete ──\n' \
    "$_completed_count" "$_planned_total" "$_passed_count" "$_failed_count" \
    "$_skipped_count" "$_todo_count" "$_incomplete_count"
else
  printf '── Summary: %s completed (planned total unavailable), %s passed, %s failed, %s skipped, %s TODO, incomplete count unavailable ──\n' \
    "$_completed_count" "$_passed_count" "$_failed_count" "$_skipped_count" "$_todo_count"
fi
if [[ "$_failed_count" -gt 0 ]]; then
  echo "Failing tests:"
  printf '  - %s\n' "${_failed_names[@]}"
fi

exit "$_run_rc"
