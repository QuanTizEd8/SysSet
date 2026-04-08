#!/bin/sh
# configure-storage.sh — fires at every container startup via the feature entrypoint.
#
# Detects whether /dev/fuse is accessible and writes the appropriate Podman
# storage driver config to /etc/containers/storage.conf (system-wide).
#
# Why system-wide (/etc/containers) and not per-user (~/.config/containers):
#   /dev/fuse availability is a host-level fact; the same driver applies to
#   every user in the container. Writing once to the global location is correct.
#   This script is invoked via the feature "entrypoint", which runs as root,
#   so writing to /etc/containers/ is always permitted.
#
# Why runtime detection (not baked in at image build time):
#   devcontainer-feature.json has no "runArgs" or "devices" field, so a feature
#   cannot request "--device=/dev/fuse". Driver selection must happen here, after
#   the host runtime has set up the container environment.
#
#   /dev/fuse accessible  →  overlay + fuse-overlayfs  (fast, space-efficient)
#   /dev/fuse unavailable →  vfs                       (always works, slower)
#
# containers.conf (userns = "keep-id") is static and is written by install.sh
# at image build time; it does not need to be touched here.

set -e

CONFIG_DIR="/etc/containers"
mkdir -p "${CONFIG_DIR}"

if [ -w /dev/fuse ]; then
    printf '[storage]\ndriver = "overlay"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
        > "${CONFIG_DIR}/storage.conf"
else
    printf '[storage]\ndriver = "vfs"\n' \
        > "${CONFIG_DIR}/storage.conf"
fi
