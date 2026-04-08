#!/bin/sh
# configure-storage.sh — entrypoint, runs as root at every container startup.
#
# 1. Remounts / with suid so newuidmap/newgidmap setuid bits are honoured
#    (Docker mounts the container rootfs nosuid by default).
# 2. Selects the best available storage driver for the named volume and
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
# 2. Determine the remote user's config directory
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
# 3. Select storage driver
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
# 4. Write storage.conf
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
# 5. Fix ownership of user config directories
# ---------------------------------------------------------------------------
if [ -n "${REMOTE_USER_HOME}" ]; then
    OWNER="$(stat -c '%u:%g' "${REMOTE_USER_HOME}")"
    mkdir -p "${REMOTE_USER_HOME}/.config/cni/net.d"
    chown "${OWNER}" "${REMOTE_USER_HOME}/.config"
    chown -R "${OWNER}" "${CONFIG_DIR}"
    chown -R "${OWNER}" "${REMOTE_USER_HOME}/.config/cni"
fi
