#!/bin/bash
# Verifies that add_root_user_config=true causes root to receive a subuid/subgid
# entry and a per-user storage.conf, in addition to the remoteUser (vscode).
# Also verifies that the two subuid ranges do not overlap.
set -e

source dev-container-features-test-lib

_GRAPH_ROOT="/var/lib/containers/storage"

# --- root is configured ---
check "root in /etc/subuid"                    grep -q "^root:" /etc/subuid
check "root in /etc/subgid"                    grep -q "^root:" /etc/subgid
check "root storage.conf exists"               test -f /root/.config/containers/storage.conf
check "root storage.conf sets overlay driver"  grep -q 'driver = "overlay"' /root/.config/containers/storage.conf
check "root storage.conf graphRoot correct"    grep -qF "graphRoot = \"${_GRAPH_ROOT}\"" /root/.config/containers/storage.conf

# --- vscode is also configured (via remoteUser) ---
check "vscode in /etc/subuid"          grep -q "^vscode:" /etc/subuid
check "vscode storage.conf exists"     test -f /home/vscode/.config/containers/storage.conf

# --- subuid ranges are non-overlapping ---
# root is processed first (offset 100000), vscode second (offset 165536)
check "root subuid offset is 100000"   bash -c 'grep "^root:" /etc/subuid | cut -d: -f2 | grep -qx 100000'
check "vscode subuid offset is 165536" bash -c 'grep "^vscode:" /etc/subuid | cut -d: -f2 | grep -qx 165536'

reportResults
