#!/bin/sh
# configure-storage.sh — fires at every container startup via the feature entrypoint.
#
# Detects whether /dev/fuse is accessible and writes the appropriate Podman
# storage driver config to the user's ~/.config/containers/ directory.
#
# Why runtime detection:
#   devcontainer-feature.json has no "runArgs" or "devices" field, so a feature
#   cannot request "--device=/dev/fuse". Driver selection must happen here, after
#   the host runtime has set up the container environment.
#
#   /dev/fuse accessible  →  overlay + fuse-overlayfs  (fast, space-efficient)
#   /dev/fuse unavailable →  vfs                       (always works, slower)
#
# This script runs as the remote user (the entrypoint is invoked in the user
# context by the dev container tooling), so HOME is the correct user home.

set -e

CONFIG_DIR="${HOME}/.config/containers"
mkdir -p "${CONFIG_DIR}"

if [ -w /dev/fuse ]; then
    printf '[storage]\ndriver = "overlay"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
        > "${CONFIG_DIR}/storage.conf"
else
    printf '[storage]\ndriver = "vfs"\n' \
        > "${CONFIG_DIR}/storage.conf"
fi

# keep-id maps the host user UID into nested containers unchanged, required for
# fuse-overlayfs to work correctly in nested environments and prevents volume
# permission mismatches.
printf '[containers]\nuserns = "keep-id"\n' \
    > "${CONFIG_DIR}/containers.conf"
