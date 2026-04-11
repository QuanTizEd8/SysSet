#!/bin/bash
# Verifies that when all per-user config options are disabled, install.sh
# succeeds and installs the shared infrastructure (packages, containers.conf,
# entrypoint, graphRoot), but writes no subuid/subgid entries and no
# per-user storage.conf files.
set -e

source dev-container-features-test-lib

# --- packages still installed ---
check "podman is installed" command -v podman
check "newuidmap is installed" command -v newuidmap

# --- system containers.conf still written ---
check "system containers.conf exists" test -f /etc/containers/containers.conf
check "containers.conf cgroupfs manager" grep -q 'cgroup_manager = "cgroupfs"' /etc/containers/containers.conf
check "containers.conf file events logger" grep -q 'events_logger = "file"' /etc/containers/containers.conf

# --- entrypoint still installed ---
check "entrypoint exists" test -f /usr/local/share/install-podman/entrypoint
check "entrypoint is executable" test -x /usr/local/share/install-podman/entrypoint

# --- no user-specific configuration written ---
check "root NOT in /etc/subuid" bash -c '! grep -q "^root:" /etc/subuid 2>/dev/null'
check "root storage.conf NOT written" bash -c '! test -f /root/.config/containers/storage.conf'

reportResults
