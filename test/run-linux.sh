#!/usr/bin/env bash
# Run Linux-native test scenarios for a given feature inside Docker containers.
#
# Usage:
#   bash test/run-linux.sh <feature> [--filter <scenario_name>]
#
# Discovers and runs every test/<feature>/linux/*.sh script in alphabetical
# order.  Each scenario script receives the repository root as its first
# positional argument and runs inside a fresh Docker container.
#
# A <name>.conf sidecar alongside each script may set:
#   IMAGE      — Docker image to use (default: ubuntu:latest).
#   NETWORK    — Set to "none" to block all networking.  The runner
#                pre-builds a base image with the feature's apt dependencies
#                so the scenario does not need network access.
#   SETUP_CMD  — Shell commands executed as root before the scenario script.
#   RUN_AS     — Username to su to before executing the scenario script.
#
# Exit code: 0 if all scenarios pass, 1 if any fail.
set -euo pipefail

FEATURE="${1:?Usage: run-linux.sh <feature> [--filter <scenario>]}"
shift

FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter)
      shift
      FILTER="${1:?--filter requires a value}"
      shift
      ;;
    *)
      echo "⛔ Unknown option: '$1'" >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIOS_DIR="${REPO_ROOT}/test/${FEATURE}/linux"

if [[ ! -d "$SCENARIOS_DIR" ]]; then
  echo "ℹ️  No Linux scenarios for '${FEATURE}' (${SCENARIOS_DIR} does not exist) — skipping."
  exit 0
fi

echo "ℹ️  Syncing _lib/ copies from lib/ before running Linux scenarios."
[ -d "${REPO_ROOT}/src" ] || bash "${REPO_ROOT}/sync-lib.sh"

_pass=0
_fail=0
_errors=()
_BASE_IMAGE=""

_sep() {
  printf '%.0s━' {1..60}
  echo
}

_require_base_image() {
  [[ -n "$_BASE_IMAGE" ]] && return
  local pkgs="bash curl ca-certificates"
  local deps_file="${REPO_ROOT}/src/${FEATURE}/dependencies/base.yaml"
  if [[ -f "$deps_file" ]]; then
    local _yaml_pkgs
    _yaml_pkgs="$(awk '/^packages:/{found=1;next} found && /^  - /{sub(/^  - /,""); print; next} found && /^[^[:space:]]/{found=0}' "$deps_file" | tr '\n' ' ' | xargs)"
    [[ -n "$_yaml_pkgs" ]] && pkgs="$_yaml_pkgs"
  fi
  _BASE_IMAGE="linux-test-base-${FEATURE}"
  echo "ℹ️  Building base image '${_BASE_IMAGE}' (packages: ${pkgs})..."
  docker build -q -t "$_BASE_IMAGE" - << DOCKERFILE
FROM ubuntu:latest
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends ${pkgs} \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE
}

for scenario in "${SCENARIOS_DIR}"/*.sh; do
  [[ -f "$scenario" ]] || continue
  name="$(basename "$scenario" .sh)"
  [[ -n "$FILTER" && "$name" != "$FILTER" ]] && continue

  # Reset per-scenario config; source sidecar if present.
  IMAGE="ubuntu:latest"
  NETWORK=""
  SETUP_CMD=""
  RUN_AS=""
  conf="${SCENARIOS_DIR}/${name}.conf"
  # shellcheck source=/dev/null
  [[ -f "$conf" ]] && source "$conf"

  # Build network-isolated base image if needed.
  net_args=()
  if [[ "$NETWORK" = "none" ]]; then
    _require_base_image
    IMAGE="$_BASE_IMAGE"
    net_args=(--network none)
  fi

  # Compose the inner command, optionally switching to RUN_AS user.
  inner_cmd="bash /repo/test/${FEATURE}/linux/${name}.sh /repo"
  if [[ -n "$RUN_AS" ]]; then
    inner_cmd="su -s /bin/bash ${RUN_AS} -c 'bash /repo/test/${FEATURE}/linux/${name}.sh /repo'"
  fi
  full_cmd="${SETUP_CMD:+${SETUP_CMD} && }${inner_cmd}"

  echo ""
  _sep
  echo "▶  ${FEATURE} / linux / ${name}"
  _sep
  if docker run --rm \
    "${net_args[@]+"${net_args[@]}"}" \
    -v "${REPO_ROOT}:/repo" \
    "$IMAGE" \
    bash -c "$full_cmd"; then
    echo "✅ PASS: ${name}"
    ((_pass++)) || true
  else
    echo "❌ FAIL: ${name}"
    _errors+=("$name")
    ((_fail++)) || true
  fi
done

echo ""
printf '%.0s═' {1..60}
echo
echo "Linux scenarios for '${FEATURE}': ${_pass} passed, ${_fail} failed."
printf '%.0s═' {1..60}
echo

if [[ ${_fail} -gt 0 ]]; then
  echo "Failing scenarios:"
  for e in "${_errors[@]}"; do
    printf '  — %s\n' "$e"
  done
  exit 1
fi
