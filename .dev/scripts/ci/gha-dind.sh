#!/usr/bin/env bash
# Run any command inside a Docker-in-Docker environment.
# Usage: dind.sh <command> [args...]
set -euo pipefail

[[ $# -gt 0 ]] || {
  printf 'usage: dind.sh <command> [args...]\n' >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${GITHUB_WORKSPACE:-}" ]] &&
  [[ -f "${GITHUB_WORKSPACE}/justfile" ]]; then
  REPO_ROOT="$GITHUB_WORKSPACE"
elif REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2> /dev/null)" &&
  [[ -f "${REPO_ROOT}/justfile" ]]; then
  :
else
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

if [[ ! -f "${REPO_ROOT}/justfile" ]]; then
  printf '⛔ Could not resolve repo root from %s\n' "$SCRIPT_DIR" >&2
  exit 1
fi

cd "$REPO_ROOT"

# GHA job containers bind-mount the runner's Docker socket at
# /var/run/docker.sock; plain `docker run` usually does not. If a host socket
# is present, remove it so clients use our inner dockerd only.
export container=docker
if [[ -d /sys/kernel/security ]] && ! mountpoint -q /sys/kernel/security; then
  mount -t securityfs none /sys/kernel/security 2> /dev/null || true
fi
if ! mountpoint -q /tmp; then
  mount -t tmpfs none /tmp 2> /dev/null || true
fi
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
  mkdir -p /sys/fs/cgroup/init
  xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2> /dev/null || true
  sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
    > /sys/fs/cgroup/cgroup.subtree_control 2> /dev/null || true
fi
mount --make-rshared / 2> /dev/null || true
find /run /var/run -iname 'docker*.pid' -delete 2> /dev/null || true
find /run /var/run -iname 'container*.pid' -delete 2> /dev/null || true
if mountpoint -q /var/run/docker.sock 2> /dev/null; then
  umount /var/run/docker.sock
elif [[ -e /var/run/docker.sock ]]; then
  rm -f /var/run/docker.sock
fi

DIND_ROOT="${REPO_ROOT}/.dind-docker"
mkdir -p "$DIND_ROOT"
dockerd --data-root "$DIND_ROOT" --storage-driver overlay2 > /tmp/dockerd.log 2>&1 &
timeout 60 sh -c 'until docker info >/dev/null 2>&1; do sleep 0.5; done'

# Docker Hub applies strict pull limits to anonymous clients. Feature tests pull
# bases like debian:latest from docker.io; authenticate here so inner builds
# use the account tier (see https://docs.docker.com/docker-hub/download-rate-limit/).
if [[ -n "${DOCKERHUB_USERNAME:-}" && -n "${DOCKERHUB_TOKEN:-}" ]]; then
  _login_attempt=1
  _login_max_attempts=3
  while :; do
    printf '%s' "${DOCKERHUB_TOKEN}" |
      docker login -u "${DOCKERHUB_USERNAME}" --password-stdin docker.io > /dev/null && break
    [[ "$_login_attempt" -ge "$_login_max_attempts" ]] && exit 1
    echo "⚠️  docker login failed (attempt ${_login_attempt}/${_login_max_attempts}); retrying in 5s" >&2
    sleep 5
    _login_attempt=$((_login_attempt + 1))
  done
fi

exec "$@"
