#!/bin/bash
# replace_existing=true (default): the Dockerfile pre-creates old_user at
# UID 1000.  The feature should evict old_user and create vscode correctly.
set -e

source dev-container-features-test-lib

# --- desired user created with correct UID ---
check "vscode user exists" bash -c 'id vscode > /dev/null 2>&1'
check "vscode has UID 1000" bash -c '[ "$(id -u vscode)" = "1000" ]'
check "vscode has GID 1000" bash -c '[ "$(id -g vscode)" = "1000" ]'

# --- home directory ---
check "home directory /home/vscode exists" test -d /home/vscode
check "home directory owned by vscode" bash -c '[ "$(stat -c "%U" /home/vscode)" = "vscode" ]'

# --- conflicting user was removed ---
check "old_user was evicted" bash -c '! id old_user > /dev/null 2>&1'

reportResults
