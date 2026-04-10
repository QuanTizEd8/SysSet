#!/bin/bash
# Alpine base image: verifies base dependencies (bash, shadow) are installed
# by the bootstrap and that the full user-creation flow works on Alpine/musl.
set -e

source dev-container-features-test-lib

# --- base dependencies installed ---
check "bash is available"    bash -c 'command -v bash'

# --- user account ---
check "vscode user exists"              bash -c 'id vscode > /dev/null 2>&1'
check "vscode has UID 1000"             bash -c '[ "$(id -u vscode)" = "1000" ]'
check "vscode has GID 1000"             bash -c '[ "$(id -g vscode)" = "1000" ]'
check "vscode primary group is vscode"  bash -c '[ "$(id -gn vscode)" = "vscode" ]'

# --- home directory ---
check "home directory /home/vscode exists"         test -d /home/vscode
check "home directory owned by uid 1000"           bash -c '[ "$(stat -c "%u" /home/vscode)" = "1000" ]'
check "home directory group-owned by gid 1000"     bash -c '[ "$(stat -c "%g" /home/vscode)" = "1000" ]'

# --- sudo ---
check "sudo binary is installed"    bash -c 'command -v sudo'
check "sudoers file exists"         test -f /etc/sudoers.d/vscode
check "sudoers grants NOPASSWD:ALL" grep -q "vscode ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/vscode

reportResults
