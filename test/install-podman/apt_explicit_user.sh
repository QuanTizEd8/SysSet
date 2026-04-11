#!/bin/bash
# Verifies that add_user_config with an explicit username configures exactly
# that user. All devcontainer-injected user options are off so only the
# explicit list path is exercised.
set -e

source dev-container-features-test-lib

_GRAPH_ROOT="/var/lib/containers/storage"
_DEVUSER_HOME="/home/devuser"

# --- devuser configured via add_user_config ---
check "devuser in /etc/subuid" grep -q "^devuser:" /etc/subuid
check "devuser in /etc/subgid" grep -q "^devuser:" /etc/subgid
check "devuser storage.conf exists" test -f "${_DEVUSER_HOME}/.config/containers/storage.conf"
check "devuser storage.conf overlay driver" grep -q 'driver = "overlay"' "${_DEVUSER_HOME}/.config/containers/storage.conf"
check "devuser storage.conf graphRoot correct" grep -qF "graphRoot = \"${_GRAPH_ROOT}\"" "${_DEVUSER_HOME}/.config/containers/storage.conf"

# --- config dir is owned by devuser ---
check "devuser .config/containers owned by devuser" bash -c '[ "$(stat -c %U /home/devuser/.config/containers)" = "devuser" ]'

# --- root should NOT be configured ---
check "root NOT in /etc/subuid" bash -c '! grep -q "^root:" /etc/subuid'
check "root storage.conf NOT written" bash -c '! test -f /root/.config/containers/storage.conf'

reportResults
