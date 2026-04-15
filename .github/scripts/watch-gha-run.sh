#!/usr/bin/env bash
# watch-commit.sh — Monitor all GHA workflow runs triggered by a commit.
#
# Usage: bash watch-commit.sh <commit-sha>
#
#   <commit-sha>  Full or short commit SHA. Short SHAs are expanded via
#                 git rev-parse (fetching from origin first if needed).
#
# Polls all workflow runs matching the commit SHA every 10 seconds until
# every run has completed. Progress and job status are printed to stderr.
#
# For each completed job:
#   Passing/skipped → job name appended to passing.log
#   Any other conclusion → full job log saved to <job-id>.log (GHA
#       timestamps stripped), and one line per failing step appended to
#       failing.log in the format:
#           <job-name> --- <step-name> --- <log-filename>
#
# All log files are written to:
#   <repo-root>/.local/logs/gha/<full-sha>/
#
# On completion, that directory path is printed to stdout.
# Exits 0 if all jobs passed/skipped, 1 if any job failed.

set -euo pipefail
export GH_PAGER=cat

COMMIT_SHA="${1:?Usage: $0 <commit-sha>}"

# Detect GitHub repo slug from git remote
REPO="$(git remote get-url origin |
  sed 's|.*github\.com[:/]\(.*\)|\1|' |
  sed 's|\.git$||')"

# Expand short SHA to full 40-char SHA; skip rev-parse if already full
if [[ ! "${COMMIT_SHA}" =~ ^[0-9a-fA-F]{40}$ ]]; then
  git fetch --quiet origin 2> /dev/null || true
  COMMIT_SHA="$(git rev-parse "${COMMIT_SHA}" 2> /dev/null || echo "${COMMIT_SHA}")"
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOGDIR="${REPO_ROOT}/.local/logs/gha/${COMMIT_SHA}"
mkdir -p "${LOGDIR}"

PASSING_LOG="${LOGDIR}/passing.log"
FAILING_LOG="${LOGDIR}/failing.log"
: > "${PASSING_LOG}"
: > "${FAILING_LOG}"

declare -A _processed # job_id → 1 (tracks already-handled jobs)
_any_failure=0
_poll_interval=10

# ---------------------------------------------------------------------------
# _ts — print a [HH:MM:SS] prefixed message to stdout
# ---------------------------------------------------------------------------
_ts() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

_ts "repo=${REPO}  commit=${COMMIT_SHA}"
_ts "logs → ${LOGDIR}/"

# ---------------------------------------------------------------------------
# _download_log <job_id>
# Downloads the full log for a job to ${LOGDIR}/<job_id>.log (stripping
# timestamps). Prints the saved filename (basename only).
# ---------------------------------------------------------------------------
_download_log() {
  local job_id="$1"
  local dest="${LOGDIR}/${job_id}.log"
  gh api "/repos/${REPO}/actions/jobs/${job_id}/logs" |
    awk '{ sub(/^[0-9T:.Z-]+[[:space:]]*/,""); print }' \
      > "${dest}" 2> /dev/null || true
  basename "${dest}"
}

# ---------------------------------------------------------------------------
# _handle_job <job-json>
# Processes one completed job. Updates passing.log / failing.log and sets
# _any_failure=1 on non-success conclusions.
# ---------------------------------------------------------------------------
_handle_job() {
  local job="$1"
  local job_id job_name conclusion
  job_id=$(jq -r '.id' <<< "${job}")
  job_name=$(jq -r '.name' <<< "${job}")
  conclusion=$(jq -r '.conclusion' <<< "${job}")

  # Skip already-processed jobs
  [[ ${_processed[${job_id}]+_} ]] && return 0
  _processed["${job_id}"]=1

  _ts "  [$(printf '%-10s' "${conclusion}")] ${job_name}"

  if [[ "${conclusion}" == "success" || "${conclusion}" == "skipped" ]]; then
    echo "${job_name}" >> "${PASSING_LOG}"
    return 0
  fi

  _any_failure=1

  # Identify failing steps
  local failing_steps
  failing_steps=$(jq -r '
    .steps[]
    | select(.conclusion == "failure" or .conclusion == "cancelled")
    | .name
  ' <<< "${job}")

  local logfile
  logfile=$(_download_log "${job_id}")

  if [[ -z "${failing_steps}" ]]; then
    echo "${job_name} --- (no failing step identified) --- ${logfile}" >> "${FAILING_LOG}"
    return 0
  fi

  while IFS= read -r step_name; do
    echo "${job_name} --- ${step_name} --- ${logfile}" >> "${FAILING_LOG}"
  done <<< "${failing_steps}"
}

# ---------------------------------------------------------------------------
# Main polling loop
# ---------------------------------------------------------------------------
while true; do
  runs_resp=$(gh api \
    "/repos/${REPO}/actions/runs?head_sha=${COMMIT_SHA}&per_page=100" 2> /dev/null) || {
    _ts 'API error — retrying...'
    sleep "${_poll_interval}"
    continue
  }

  total_runs=$(jq '.total_count' <<< "${runs_resp}")
  if [[ "${total_runs}" -eq 0 ]]; then
    _ts 'no workflow runs found yet, waiting...'
    sleep "${_poll_interval}"
    continue
  fi

  all_done=true
  in_progress_jobs=()

  while IFS= read -r run; do
    run_id=$(jq -r '.id' <<< "${run}")
    run_status=$(jq -r '.status' <<< "${run}")

    [[ "${run_status}" != "completed" ]] && all_done=false

    jobs_resp=$(gh api \
      "/repos/${REPO}/actions/runs/${run_id}/jobs?per_page=100" 2> /dev/null) || continue

    while IFS= read -r job; do
      job_status=$(jq -r '.status' <<< "${job}")
      if [[ "${job_status}" == "completed" ]]; then
        _handle_job "${job}"
      elif [[ "${job_status}" == "in_progress" ]]; then
        in_progress_jobs+=("$(jq -r '.name' <<< "${job}")")
      fi
    done < <(jq -c '.jobs[]' <<< "${jobs_resp}")

  done < <(jq -c '.workflow_runs[]' <<< "${runs_resp}")

  if [[ "${all_done}" == "true" ]]; then
    _ts 'all workflow runs completed'
    break
  fi

  if [[ ${#in_progress_jobs[@]} -gt 0 ]]; then
    _ts "in progress (${#in_progress_jobs[@]}): ${in_progress_jobs[*]}"
  fi

  sleep "${_poll_interval}"
done

echo '' >&2
_ts "${#_processed[@]} job(s) finished — $(wc -l < "${PASSING_LOG}" | tr -d ' ') passed, $(wc -l < "${FAILING_LOG}" | tr -d ' ') failure(s) logged"
echo "${LOGDIR}"
exit "${_any_failure}"
