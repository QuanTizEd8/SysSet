#!/bin/bash
# replace_existing=false with the user already correctly configured: the
# feature should recognise the existing account and pass through without error.
set -e

source dev-container-features-test-lib

# --- user is intact ---
check "vscode user exists"            bash -c 'id vscode > /dev/null 2>&1'
check "vscode has UID 1000"           bash -c '[ "$(id -u vscode)" = "1000" ]'
check "vscode has GID 1000"           bash -c '[ "$(id -g vscode)" = "1000" ]'
check "vscode primary group is vscode" bash -c '[ "$(id -gn vscode)" = "vscode" ]'

# --- home directory unchanged ---
check "home directory /home/vscode exists"    test -d /home/vscode
check "home directory owned by vscode"        bash -c '[ "$(stat -c "%U" /home/vscode)" = "vscode" ]'

reportResults
