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

# A failure here can be a transient image-pull/registry blip (--rm means the
# container is always cleaned up on exit, success or failure, so a retry is
# safe to re-run) or a genuine test failure — there's no cheap way to tell
# them apart from outside the container, so this is a small, blind, bounded
# retry: worth it for the transient case, bounded cost for the real-failure
# case (one extra run before reporting the same failure).
_attempt=1
_max_attempts=2
while :; do
  if docker run --rm \
    "${_NAME_ARGS[@]+"${_NAME_ARGS[@]}"}" \
    "${_NET_ARGS[@]+"${_NET_ARGS[@]}"}" \
    "${_LOG_VOL_ARGS[@]+"${_LOG_VOL_ARGS[@]}"}" \
    "${_BIND_VOL_ARGS[@]+"${_BIND_VOL_ARGS[@]}"}" \
    "${_EXTRA_ENV[@]+"${_EXTRA_ENV[@]}"}" \
    -e REPO_ROOT=/repo \
    -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    "$_IMAGE" \
    sh -c "$_RUN_CMD"; then
    break
  fi
  [[ "$_attempt" -ge "$_max_attempts" ]] && exit 1
  echo "⚠️  docker run failed (attempt ${_attempt}/${_max_attempts}); retrying in 5s" >&2
  sleep 5
  _attempt=$((_attempt + 1))
done
