#!/bin/bash
# Verifies that add_container_user_config=true configures the user injected via
# _CONTAINER_USER (set by the devcontainer CLI from the containerUser field).
# add_remote_user_config and add_current_user_config are both off so only
# the containerUser path is exercised.
set -e

source dev-container-features-test-lib

# --- vscode configured via _CONTAINER_USER ---
check "vscode in /etc/subuid" grep -q "^vscode:" /etc/subuid
check "vscode in /etc/subgid" grep -q "^vscode:" /etc/subgid
check "vscode storage.conf exists" test -f /home/vscode/.config/containers/storage.conf
check "vscode storage.conf overlay driver" grep -q 'driver = "overlay"' /home/vscode/.config/containers/storage.conf

# --- root should NOT be configured ---
check "root NOT in /etc/subuid" bash -c '! grep -q "^root:" /etc/subuid'
check "root storage.conf NOT written" bash -c '! test -f /root/.config/containers/storage.conf'

reportResults
