#!/bin/sh
# configure-storage.sh — entrypoint, runs as root at every container startup.
#
# Prepares the container environment for rootless Podman:
#   1. Remounts / with suid so newuidmap/newgidmap setuid bits are honoured.
#   2. Creates /dev/net/tun for slirp4netns networking.
#   3. Remounts /proc unrestricted so crun can mount procfs in inner containers.
#   4. Writes storage.conf pointing Podman at the named volume with native overlay.
#
# Native overlay (kernel >= 5.12, which covers all modern Docker hosts) on the
# named volume avoids both the overlay-on-overlay problem and fuse-overlayfs's
# nested-userns noexec issue.  No fallback driver is provided — if overlay
# doesn't work, Podman will report a clear error.

set -e

GRAPH_ROOT="/var/lib/containers/storage"

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

# ---------------------------------------------------------------------------
# 4. Determine the remote user's config directory
# ---------------------------------------------------------------------------
REMOTE_USER_HOME=$(cat /usr/local/lib/podman-remote-user-home 2>/dev/null)

if [ -z "${REMOTE_USER_HOME}" ]; then
    CONFIG_DIR="/etc/containers"
else
    # Rootless Podman ignores system graphRoot; user-level config is required.
    CONFIG_DIR="${REMOTE_USER_HOME}/.config/containers"
fi

mkdir -p "${CONFIG_DIR}" "${GRAPH_ROOT}"

# ---------------------------------------------------------------------------
# 5. Write storage.conf — native overlay on the named volume
# ---------------------------------------------------------------------------
cat > "${CONFIG_DIR}/storage.conf" <<EOF
[storage]
driver = "overlay"
graphRoot = "${GRAPH_ROOT}"
EOF

# ---------------------------------------------------------------------------
# 6. Fix ownership of user config directories
#
# Several directories under ~/.config may have been created by this script
# (running as root).  Podman also creates subdirectories at runtime (cni,
# containers, etc.).  Use a single recursive chown on ~/.config to cover
# everything — this is fast (few files) and avoids chasing individual paths.
# ---------------------------------------------------------------------------
if [ -n "${REMOTE_USER_HOME}" ]; then
    OWNER="$(stat -c '%u:%g' "${REMOTE_USER_HOME}")"
    mkdir -p "${REMOTE_USER_HOME}/.config/cni/net.d"
    chown -R "${OWNER}" "${REMOTE_USER_HOME}/.config"
fi
