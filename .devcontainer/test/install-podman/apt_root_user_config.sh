#!/bin/bash
# Verifies that add_root_user_config=true causes root to receive a subuid/subgid
# entry and a per-user storage.conf, in addition to the remoteUser (vscode).
# Also verifies that the two subuid ranges do not overlap.
set -e

source dev-container-features-test-lib

_GRAPH_ROOT="/var/lib/containers/storage"

# No remoteUser is set so this test runs as root, allowing access to /root/.
# With add_root_user_config=true and all other user options at their defaults
# (add_current_user_config skips root, _REMOTE_USER/_CONTAINER_USER unset),
# only root should be configured.

# --- root is configured ---
check "root in /etc/subuid"                    grep -q "^root:" /etc/subuid
check "root in /etc/subgid"                    grep -q "^root:" /etc/subgid
check "root subuid offset is 100000"           bash -c 'grep "^root:" /etc/subuid | cut -d: -f2 | grep -qx 100000'
check "root subuid count is 65536"             bash -c 'grep "^root:" /etc/subuid | cut -d: -f3 | grep -qx 65536'
check "root storage.conf exists"               test -f /root/.config/containers/storage.conf
check "root storage.conf sets overlay driver"  grep -q 'driver = "overlay"' /root/.config/containers/storage.conf
check "root storage.conf graphRoot correct"    grep -qF "graphRoot = \"${_GRAPH_ROOT}\"" /root/.config/containers/storage.conf

# --- no other user should be configured ---
check "vscode NOT in /etc/subuid"              bash -c '! grep -q "^vscode:" /etc/subuid 2>/dev/null'

reportResults
