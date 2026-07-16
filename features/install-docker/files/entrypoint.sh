#!/bin/sh
#
# Docker-in-Docker container entrypoint.
#
# Runs at container start (deployed as the feature entrypoint). It prepares the
# container for a nested daemon — cgroup v2 delegation, shared mount propagation,
# security/tmp mounts (the Moby hack/dind pattern) — then starts containerd and
# dockerd and execs the container command. Configuration comes from the sourced
# `entrypoint.sh.conf` (MODE, DEFAULT_ADDRESS_POOL, AZURE_DNS_AUTO_DETECTION,
# DISABLE_IP6TABLES, IPTABLES, IPTABLES_SWITCH_AT_RUNTIME). `warn()` and the
# config sourcing are provided by the deployed lifecycle-script boilerplate.

# --- Container preparation (Moby hack/dind) --------------------------------

prepare_apparmor() {
  # Signal AppArmor that we are a Docker-style container.
  export container=docker
}

mount_security_fs() {
  [ -d /sys/kernel/security ] || return 0
  grep -q ' /sys/kernel/security ' /proc/mounts 2> /dev/null && return 0
  mount -t securityfs none /sys/kernel/security 2> /dev/null ||
    warn "could not mount /sys/kernel/security (AppArmor may be unavailable)"
}

mount_tmp() {
  grep -q ' /tmp ' /proc/mounts 2> /dev/null && return 0
  mount -t tmpfs none /tmp 2> /dev/null || warn "could not mount /tmp as tmpfs"
}

setup_cgroup_v2_delegation() {
  [ -f /sys/fs/cgroup/cgroup.controllers ] || return 0
  # Docker places container processes in the cgroup v2 root; the kernel's
  # "no internal process" rule then blocks enabling controllers for children.
  # Move processes into /init so the root becomes process-free, then enable all
  # available controllers for the subtree. Mirrors moby/moby hack/dind.
  if ! mkdir -p /sys/fs/cgroup/init 2> /dev/null; then
    warn "could not create /sys/fs/cgroup/init; cgroup v2 delegation skipped"
    return 0
  fi
  xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2> /dev/null || true
  sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
    > /sys/fs/cgroup/cgroup.subtree_control 2> /dev/null ||
    warn "could not enable cgroup v2 controllers in the subtree"
}

ensure_rshared_root() {
  # dockerd needs shared mount propagation for bind mounts into containers.
  mount --make-rshared / 2> /dev/null ||
    warn "could not set '/' propagation to rshared (expected on macOS Docker Desktop)"
}

clean_pid_files() {
  rm -f /run/docker.pid /var/run/docker.pid \
    /run/containerd/containerd.pid /run/docker/containerd/containerd.pid 2> /dev/null || true
}

# --- iptables (optional runtime switch) ------------------------------------

maybe_switch_iptables() {
  [ "${IPTABLES_SWITCH_AT_RUNTIME:-false}" = "true" ] || return 0
  command -v update-alternatives > /dev/null 2>&1 || return 0
  backend="${IPTABLES:-auto}"
  [ "$backend" = "auto" ] && return 0
  update-alternatives --set iptables "/usr/sbin/iptables-${backend}" 2> /dev/null || true
  update-alternatives --set ip6tables "/usr/sbin/ip6tables-${backend}" 2> /dev/null || true
}

# --- Daemons ---------------------------------------------------------------

containerd_running() {
  [ -S /run/containerd/containerd.sock ]
}

start_containerd() {
  containerd_running && return 0
  command -v containerd > /dev/null 2>&1 || {
    warn "containerd not found on PATH; cannot start Docker-in-Docker"
    return 1
  }
  if [ -f /etc/containerd/config.toml ]; then
    (containerd --config /etc/containerd/config.toml > /tmp/containerd.log 2>&1) &
  else
    (containerd > /tmp/containerd.log 2>&1) &
  fi
  i=0
  while ! containerd_running && [ "$i" -lt 30 ]; do
    sleep 0.5
    i=$((i + 1))
  done
  containerd_running || warn "containerd did not become ready (see /tmp/containerd.log)"
}

is_azure() {
  grep -qi microsoft /sys/class/dmi/id/sys_vendor 2> /dev/null
}

docker_running() {
  docker info > /dev/null 2>&1
}

start_dockerd() {
  docker_running && return 0
  command -v dockerd > /dev/null 2>&1 || {
    warn "dockerd not found on PATH; cannot start Docker-in-Docker"
    return 1
  }
  set -- dockerd --containerd=/run/containerd/containerd.sock
  [ -n "${DEFAULT_ADDRESS_POOL:-}" ] && set -- "$@" --default-address-pool "${DEFAULT_ADDRESS_POOL}"
  [ "${DISABLE_IP6TABLES:-false}" = "true" ] && set -- "$@" --ip6tables=false
  if [ "${AZURE_DNS_AUTO_DETECTION:-true}" = "true" ] && is_azure; then
    set -- "$@" --dns 168.63.129.16
  fi
  ("$@" > /tmp/dockerd.log 2>&1) &
  i=0
  while ! docker_running && [ "$i" -lt 30 ]; do
    sleep 1
    i=$((i + 1))
  done
  docker_running || warn "dockerd did not become ready (see /tmp/dockerd.log)"
}

# --- Main ------------------------------------------------------------------

prepare_apparmor
mount_security_fs
mount_tmp
setup_cgroup_v2_delegation
ensure_rshared_root
clean_pid_files
maybe_switch_iptables
start_containerd
start_dockerd

# Run the container's command (default to staying alive when none was given).
if [ "$#" -eq 0 ]; then
  set -- sleep infinity
fi
exec "$@"
