#!/bin/sh
# configure-storage.sh — entrypoint, runs as root at every container startup.
#
# Prepares the container environment for rootless Podman:
#   1. Remounts / with suid so newuidmap/newgidmap setuid bits are honoured.
#   2. Creates /dev/net/tun for slirp4netns networking.
#   3. Remounts /proc unrestricted so crun can mount procfs in inner containers.
#
# Storage configuration (storage.conf) is written at build time by install.sh.

set -e

# ---------------------------------------------------------------------------
# 1. Enable setuid binaries (newuidmap / newgidmap)
#
# Docker/containerd mount the container rootfs with nosuid, which prevents
# newuidmap from escalating to write /proc/<pid>/uid_map.  With CAP_SYS_ADMIN
# (granted via capAdd in devcontainer-feature.json), we can remount / to
# restore suid.  This is much narrower than --privileged.
# ---------------------------------------------------------------------------
mount -o remount,suid / 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Ensure /dev/net/tun exists
#
# slirp4netns (rootless container networking) requires the TUN device.
# Docker does not create /dev/net/tun in non-privileged containers.
# With CAP_MKNOD we can create the device node ourselves.
# ---------------------------------------------------------------------------
if [ ! -e /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 0666 /dev/net/tun 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 3. Remount /proc unrestricted
#
# Docker masks sensitive /proc paths by bind-mounting /dev/null or tmpfs
# over them, and mounts /proc/sys read-only.  The kernel treats a procfs
# with ANY masked/restricted submounts as "restricted" and refuses to let
# child user namespaces mount a fresh unrestricted procfs — which is exactly
# what crun needs to do when setting up inner containers.
#
# Mounting a new procfs replaces Docker's restricted one with a clean mount,
# removing all masks in one operation.  This is safe: we already run with
# CAP_SYS_ADMIN and seccomp=unconfined, so the masked paths offer no
# additional protection.  This is the same thing --privileged does.
# ---------------------------------------------------------------------------
mount -t proc proc /proc 2>/dev/null || true
