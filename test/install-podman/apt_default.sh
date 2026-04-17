#!/bin/bash
# Default options with remoteUser="vscode".
# Verifies packages, setuid binaries, vscode user configuration,
# system containers.conf, and the startup entrypoint.
# Root should NOT be configured (add_users does not include root by default).
set -e

source dev-container-features-test-lib

_GRAPH_ROOT="/var/lib/containers/storage"
_VSCODE_HOME="/home/vscode"
_VSCODE_STORAGE_CONF="${_VSCODE_HOME}/.config/containers/storage.conf"

# --- Packages ---
check "podman is installed" command -v podman
check "slirp4netns is installed" command -v slirp4netns
check "passt is installed" command -v passt
check "newuidmap is installed" command -v newuidmap
check "newgidmap is installed" command -v newgidmap

# --- setuid bits on newuidmap / newgidmap ---
check "newuidmap is setuid root" bash -c 'test -u "$(command -v newuidmap)"'
check "newgidmap is setuid root" bash -c 'test -u "$(command -v newgidmap)"'

# --- vscode subuid / subgid entries exist ---
check "vscode in /etc/subuid" grep -q "^vscode:" /etc/subuid
check "vscode in /etc/subgid" grep -q "^vscode:" /etc/subgid

# --- vscode subuid range is 65536 entries at offset 100000 ---
check "vscode subuid offset is 100000" bash -c 'grep "^vscode:" /etc/subuid | cut -d: -f2 | grep -qx 100000'
check "vscode subuid count is 65536" bash -c 'grep "^vscode:" /etc/subuid | cut -d: -f3 | grep -qx 65536'

# --- per-user storage.conf for vscode ---
check "vscode storage.conf exists" test -f "${_VSCODE_STORAGE_CONF}"
check "vscode storage.conf sets overlay driver" grep -q 'driver = "overlay"' "${_VSCODE_STORAGE_CONF}"
check "vscode storage.conf sets correct graphRoot" grep -qF "graphRoot = \"${_GRAPH_ROOT}\"" "${_VSCODE_STORAGE_CONF}"

# --- storage.conf ownership ---
check "vscode .config/containers owned by vscode" bash -c '[ "$(stat -c %U /home/vscode/.config/containers)" = "vscode" ]'

# --- system containers.conf ---
check "system containers.conf exists" test -f /etc/containers/containers.conf
check "containers.conf sets cgroupfs manager" grep -q 'cgroup_manager = "cgroupfs"' /etc/containers/containers.conf
check "containers.conf sets file events logger" grep -q 'events_logger = "file"' /etc/containers/containers.conf

# --- entrypoint ---
check "entrypoint script exists" test -f /usr/local/share/install-podman/entrypoint
check "entrypoint is executable" test -x /usr/local/share/install-podman/entrypoint
check "entrypoint runs make-rshared" grep -q 'mount --make-rshared /' /usr/local/share/install-podman/entrypoint

# --- root should NOT be configured ---
check "root NOT in /etc/subuid" bash -c '! grep -q "^root:" /etc/subuid'
check "root storage.conf NOT written" bash -c '! test -f /root/.config/containers/storage.conf'

reportResults
