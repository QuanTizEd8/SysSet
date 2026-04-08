#!/bin/sh
# configure-storage.sh — entrypoint, runs as root at every container startup.
#
# 1. Remounts / with suid so newuidmap/newgidmap setuid bits are honoured
#    (Docker mounts the container rootfs nosuid by default).
# 2. Remounts /proc/sys as rw so crun can write ping_group_range when
#    setting up inner containers' network namespaces.
# 3. Selects the best available storage driver for the named volume and
#    writes the remote user's storage.conf.
#
# Storage driver selection (in preference order):
#
#   native overlay   — Kernel >= 5.12 supports unprivileged overlay mounts
#                      in user namespaces.  The named volume provides a real
#                      filesystem (ext4/xfs/…), avoiding overlay-on-overlay.
#                      No FUSE involved, so no noexec issue.  Best option.
#
#   vfs              — Copies all image layers into the graphRoot directory.
#                      Slower and uses more space, but works on any kernel.
#                      The named volume makes this tolerable by persisting
#                      pulled images across container restarts.
#
#   (fuse-overlayfs is deliberately skipped when running inside a container.
#    FUSE mounts inherit noexec in nested user namespaces, causing exec from
#    inner containers to fail with EINVAL.)

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
# With CAP_SYS_ADMIN we can create the device node ourselves.
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
# 3. Determine the remote user's config directory
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
# 4. Select storage driver
#
# Check kernel version for native overlay support in user namespaces (>= 5.12).
# The graphRoot lives on the named volume, which is a real filesystem — native
# overlay can layer on top of it without the overlay-on-overlay restriction.
# ---------------------------------------------------------------------------
KERNEL_VER=$(uname -r | cut -d. -f1-2)
KERNEL_MAJOR=$(echo "${KERNEL_VER}" | cut -d. -f1)
KERNEL_MINOR=$(echo "${KERNEL_VER}" | cut -d. -f2)

if [ "${KERNEL_MAJOR}" -gt 5 ] 2>/dev/null ||
   { [ "${KERNEL_MAJOR}" -eq 5 ] && [ "${KERNEL_MINOR}" -ge 12 ]; } 2>/dev/null; then
    DRIVER="overlay"
else
    DRIVER="vfs"
fi

# ---------------------------------------------------------------------------
# 5. Handle storage driver mismatch
#
# The named volume persists across devcontainer rebuilds.  If the previous
# build used a different driver (e.g. VFS from the old config, overlay now),
# Podman refuses to start: "User-selected graph driver overwritten by graph
# driver from database".  Detect this and wipe stale data.
# ---------------------------------------------------------------------------
STALE=""
if [ "${DRIVER}" = "overlay" ] && [ -d "${GRAPH_ROOT}/vfs" ]; then
    STALE=yes
elif [ "${DRIVER}" = "vfs" ] && [ -d "${GRAPH_ROOT}/overlay" ]; then
    STALE=yes
fi
if [ "${STALE}" = "yes" ]; then
    echo "podman-configure-storage: driver changed to ${DRIVER}, clearing stale storage data" >&2
    # Podman stores layers, images, containers under <driver>-* dirs + libpod/.
    # Wipe everything in the graphRoot so Podman can start clean.
    rm -rf "${GRAPH_ROOT:?}"/*
fi

# ---------------------------------------------------------------------------
# 6. Write storage.conf
# ---------------------------------------------------------------------------
if [ "${DRIVER}" = "overlay" ]; then
    cat > "${CONFIG_DIR}/storage.conf" <<EOF
[storage]
driver = "overlay"
graphRoot = "${GRAPH_ROOT}"
EOF
else
    cat > "${CONFIG_DIR}/storage.conf" <<EOF
[storage]
driver = "vfs"
graphRoot = "${GRAPH_ROOT}"
EOF
fi

# ---------------------------------------------------------------------------
# 7. Fix ownership of user config directories
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
