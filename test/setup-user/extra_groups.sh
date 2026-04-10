#!/bin/bash
# extra_groups=builders,testers: vscode is added to both supplementary groups
# (pre-created in the Dockerfile).
set -e

source dev-container-features-test-lib

# --- user account ---
check "vscode user exists"    bash -c 'id vscode > /dev/null 2>&1'

# --- supplementary group membership ---
check "vscode is in group builders"   bash -c 'groups vscode | tr " " "\n" | grep -qx "builders"'
check "vscode is in group testers"    bash -c 'groups vscode | tr " " "\n" | grep -qx "testers"'

reportResults
