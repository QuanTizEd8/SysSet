#!/usr/bin/env bash
# Usage: run-in-container.sh --image <image> --run <cmd>
#                            [--name <label>]
#                            [--log-bind-dir <host-dir>]
#                            [--bind HOST:CONTAINER[:ro]]  (repeatable)
#                            [--network-none]
#                            [--env KEY=VAL] ...
#
# Mounts only the specified paths (via --bind) into the container at /repo.
# With --log-bind-dir, mounts a host directory at /log-out (rw) for post-run log copy.
set -euo pipefail

_IMAGE="" _RUN_CMD="" _NAME="" _LOG_BIND_DIR="" _NET_ARGS=() _EXTRA_ENV=() _BIND_VOL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      _IMAGE="$2"
      shift 2
      ;;
    --run)
      _RUN_CMD="$2"
      shift 2
      ;;
    --name)
      _NAME="$2"
      shift 2
      ;;
    --log-bind-dir)
      _LOG_BIND_DIR="$2"
      shift 2
      ;;
    --bind)
      _BIND_VOL_ARGS+=(-v "$2")
      shift 2
      ;;
    --network-none)
      _NET_ARGS=("--network" "none")
      shift
      ;;
    --env)
      _EXTRA_ENV+=("-e" "$2")
      shift 2
      ;;
    *)
      printf 'Unknown arg: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$_IMAGE" || -z "$_RUN_CMD" ]] && {
  echo "⛔ --image and --run required" >&2
  exit 1
}

_NAME_ARGS=()
[[ -n "$_NAME" ]] && _NAME_ARGS=("--name" "$_NAME")

_LOG_VOL_ARGS=()
if [[ -n "$_LOG_BIND_DIR" ]]; then
  mkdir -p "$_LOG_BIND_DIR"
  _LOG_VOL_ARGS=(-v "${_LOG_BIND_DIR}:/log-out:rw")
fi

# Docker reserves exit codes 125-127 for failures in Docker itself (bad
# image, failed pull, couldn't invoke/find the command) — any other exit code
# is the contained command's own, passed through unchanged. Only retry the
# 125-127 case: it's plausibly a transient registry/pull blip (--rm means the
# container is always cleaned up on exit, so a retry is safe), whereas the
# contained command's own exit code is a real, usually deterministic result
# (e.g. a failing test) that retrying would just reproduce identically while
# wasting a full extra run. See https://docs.docker.com/engine/reference/run/#exit-status
_attempt=1
_max_attempts=2
while :; do
  docker run --rm \
    "${_NAME_ARGS[@]+"${_NAME_ARGS[@]}"}" \
    "${_NET_ARGS[@]+"${_NET_ARGS[@]}"}" \
    "${_LOG_VOL_ARGS[@]+"${_LOG_VOL_ARGS[@]}"}" \
    "${_BIND_VOL_ARGS[@]+"${_BIND_VOL_ARGS[@]}"}" \
    "${_EXTRA_ENV[@]+"${_EXTRA_ENV[@]}"}" \
    -e REPO_ROOT=/repo \
    -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    "$_IMAGE" \
    sh -c "$_RUN_CMD" && exit 0
  _rc=$?
  if [[ "$_rc" -lt 125 || "$_rc" -gt 127 ]]; then
    exit "$_rc"
  fi
  [[ "$_attempt" -ge "$_max_attempts" ]] && exit "$_rc"
  echo "⚠️  docker run failed with a Docker-level error (exit ${_rc}, attempt ${_attempt}/${_max_attempts}); retrying in 5s" >&2
  sleep 5
  _attempt=$((_attempt + 1))
done
