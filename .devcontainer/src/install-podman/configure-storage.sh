#!/bin/sh
# configure-storage.sh - fires at every container startup via the feature entrypoint.
#
# Writes storage.conf for the remote (non-root) user, directing Podman's
# graphRoot to the dedicated named volume at /var/lib/containers/storage.
#
# Why write to the user config (~/.config/containers/storage.conf):
#   In rootless mode, Podman ignores the graphRoot from /etc/containers/storage.conf
#   and always defaults to $HOME/.local/share/containers/storage. Driver options
#   (mount_program etc.) are read from the system config, but graphRoot is not.
#   Writing the user-level config is the only way to redirect graphRoot.
#   Since this entrypoint runs as root, we find the remote user from /etc/passwd
#   and write their config directly.
#
# Why a dedicated volume for graphRoot (/var/lib/containers/storage):
#   With VFS, each container run copies image layers to the graphRoot. On the
#   container's overlayfs root this works but wastes space/time on ephemeral
#   storage. The dedicated named volume persists across container restarts, so
#   pulled images are cached and not re-pulled or re-copied on every run.
#
# Why VFS and not fuse-overlayfs:
#   fuse-overlayfs creates FUSE mounts. FUSE mounts inherit noexec when created
#   inside a user namespace (the dev container itself is already a user namespace).
#   Rootless Podman always creates another user namespace for its containers, and
#   exec from a FUSE mount within a nested user namespace returns EINVAL.
#   VFS copies files onto the graphRoot filesystem directly - no new mounts, no
#   exec restriction. This is the correct and only viable driver in this context.
#
#   On a native Linux host (root FS is not overlayfs), fuse-overlayfs would work
#   because Podman is not running inside a pre-existing user namespace. The check
#   below uses root FS type as a proxy to detect this case.
#
# containers.conf (userns = "keep-id") is static; written by install.sh.

set -e

GRAPH_ROOT="/var/lib/containers/storage"

# Read the remote user's home directory saved by install.sh at image build time.
# Using a saved value (rather than scanning /etc/passwd) avoids picking the wrong
# user when multiple UIDs >= 1000 exist in the base image (e.g. ubuntu user).
REMOTE_USER_HOME=$(cat /usr/local/lib/podman-remote-user-home 2>/dev/null)

if [ -z "${REMOTE_USER_HOME}" ]; then
    CONFIG_DIR="/etc/containers"
else
    CONFIG_DIR="${REMOTE_USER_HOME}/.config/containers"
fi

mkdir -p "${CONFIG_DIR}" "${GRAPH_ROOT}"

# If the container's root FS is overlayfs, we are inside a containerized
# environment where exec from FUSE mounts fails - use VFS unconditionally.
# Otherwise (native Linux host), fuse-overlayfs is viable if /dev/fuse is present.
ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null \
    || awk '$5=="/" {print $9}' /proc/self/mountinfo | head -1)

if [ "${ROOT_FSTYPE}" != "overlay" ] && [ -w /dev/fuse ]; then
    DRIVER="overlay"
else
    DRIVER="vfs"
fi

if [ "${DRIVER}" = "overlay" ]; then
    printf '[storage]\ndriver = "overlay"\ngraphRoot = "%s"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
        "${GRAPH_ROOT}" > "${CONFIG_DIR}/storage.conf"
else
    printf '[storage]\ndriver = "vfs"\ngraphRoot = "%s"\n' \
        "${GRAPH_ROOT}" > "${CONFIG_DIR}/storage.conf"
fi

# Fix ownership so the user can read/write their own config and any sibling
# directories Podman may create under ~/.config/ (e.g. cni, cni/net.d).
# mkdir -p creates ~/.config as root if it did not already exist, so we must
# own it and pre-create known subdirectories Podman will need.
if [ -n "${REMOTE_USER_HOME}" ]; then
    OWNER="$(stat -c '%u:%g' "${REMOTE_USER_HOME}")"
    mkdir -p "${REMOTE_USER_HOME}/.config/cni/net.d"
    chown "${OWNER}" "${REMOTE_USER_HOME}/.config"
    chown -R "${OWNER}" "${CONFIG_DIR}"
    chown -R "${OWNER}" "${REMOTE_USER_HOME}/.config/cni"
fi
