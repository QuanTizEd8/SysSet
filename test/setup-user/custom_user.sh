#!/bin/bash
# Custom username/user_id/group_id/group_name: username=devuser, user_id=2000,
# group_id=2000, group_name=devgroup.  Verifies all custom values are applied.
set -e

source dev-container-features-test-lib

# --- user account ---
check "devuser user exists"            bash -c 'id devuser > /dev/null 2>&1'
check "devuser has UID 2000"           bash -c '[ "$(id -u devuser)" = "2000" ]'
check "devuser has GID 2000"           bash -c '[ "$(id -g devuser)" = "2000" ]'
check "devuser primary group is devgroup"  bash -c '[ "$(id -gn devuser)" = "devgroup" ]'

# --- group ---
check "devgroup group exists"          bash -c 'getent group devgroup > /dev/null 2>&1'
check "devgroup has GID 2000"          bash -c '[ "$(getent group devgroup | cut -d: -f3)" = "2000" ]'

# --- home directory ---
check "home directory /home/devuser exists"      test -d /home/devuser
check "home directory owned by devuser"          bash -c '[ "$(stat -c "%U" /home/devuser)" = "devuser" ]'

# --- default user not created ---
check "user vscode was NOT created"    bash -c '! id vscode > /dev/null 2>&1'

reportResults
