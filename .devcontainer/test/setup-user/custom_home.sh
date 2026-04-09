#!/bin/bash
# home_dir=/workspaces/myapp: home directory is created at the specified path.
set -e

source dev-container-features-test-lib

# --- user account ---
check "vscode user exists"    bash -c 'id vscode > /dev/null 2>&1'

# --- custom home directory ---
check "custom home /workspaces/myapp exists"    test -d /workspaces/myapp
check "custom home owned by vscode"             bash -c '[ "$(stat -c "%U" /workspaces/myapp)" = "vscode" ]'
check "custom home group-owned by vscode"       bash -c '[ "$(stat -c "%G" /workspaces/myapp)" = "vscode" ]'
check "passwd home matches custom path"         bash -c '[ "$(awk -F: '\''$1=="vscode"{print $6}'\'' /etc/passwd)" = "/workspaces/myapp" ]'

# --- default path NOT created ---
check "/home/vscode was NOT created"    bash -c '! test -d /home/vscode'

reportResults
