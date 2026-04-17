#!/bin/bash
# Verifies that multiple users given via add_users are each configured
# with their own subuid/subgid entry and storage.conf, and that their subuid
# ranges are non-overlapping.
set -e

source dev-container-features-test-lib

_GRAPH_ROOT="/var/lib/containers/storage"

# --- alice configured ---
check "alice in /etc/subuid" grep -q "^alice:" /etc/subuid
check "alice in /etc/subgid" grep -q "^alice:" /etc/subgid
check "alice storage.conf exists" test -f /home/alice/.config/containers/storage.conf
check "alice storage.conf overlay driver" grep -q 'driver = "overlay"' /home/alice/.config/containers/storage.conf
check "alice storage.conf graphRoot correct" grep -qF "graphRoot = \"${_GRAPH_ROOT}\"" /home/alice/.config/containers/storage.conf
check "alice .config owned by alice" bash -c '[ "$(stat -c %U /home/alice/.config/containers)" = "alice" ]'

# --- bob configured ---
check "bob in /etc/subuid" grep -q "^bob:" /etc/subuid
check "bob in /etc/subgid" grep -q "^bob:" /etc/subgid
check "bob storage.conf exists" test -f /home/bob/.config/containers/storage.conf
check "bob storage.conf overlay driver" grep -q 'driver = "overlay"' /home/bob/.config/containers/storage.conf
check "bob storage.conf graphRoot correct" grep -qF "graphRoot = \"${_GRAPH_ROOT}\"" /home/bob/.config/containers/storage.conf
check "bob .config owned by bob" bash -c '[ "$(stat -c %U /home/bob/.config/containers)" = "bob" ]'

# --- subuid ranges do not overlap ---
# alice is first (offset 100000), bob is second (offset 165536)
check "alice subuid offset is 100000" bash -c 'grep "^alice:" /etc/subuid | cut -d: -f2 | grep -qx 100000'
check "alice subuid count is 65536" bash -c 'grep "^alice:" /etc/subuid | cut -d: -f3 | grep -qx 65536'
check "bob subuid offset is 165536" bash -c 'grep "^bob:" /etc/subuid | cut -d: -f2 | grep -qx 165536'
check "bob subuid count is 65536" bash -c 'grep "^bob:" /etc/subuid | cut -d: -f3 | grep -qx 65536'

reportResults
