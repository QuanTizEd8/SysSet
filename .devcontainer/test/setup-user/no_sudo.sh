#!/bin/bash
# sudo_access=false: user is created but no sudo is configured.
set -e

source dev-container-features-test-lib

# --- user account ---
check "vscode user exists"    bash -c 'id vscode > /dev/null 2>&1'
check "vscode has UID 1000"   bash -c '[ "$(id -u vscode)" = "1000" ]'
check "vscode has GID 1000"   bash -c '[ "$(id -g vscode)" = "1000" ]'

# --- home directory ---
check "home directory /home/vscode exists"    test -d /home/vscode
check "home directory owned by vscode"        bash -c '[ "$(stat -c "%U" /home/vscode)" = "vscode" ]'

# --- no sudo drop-in ---
check "no sudoers file for vscode"    bash -c '! test -f /etc/sudoers.d/vscode'

reportResults
