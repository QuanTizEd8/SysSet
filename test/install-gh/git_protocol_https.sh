#!/bin/bash
# git_protocol=https + add_remote_user_config=true (vscode user).
# Verifies gh config file under /home/vscode contains git_protocol: https.
set -e

source dev-container-features-test-lib

# --- gh installed ---
check "gh on PATH" command -v gh
check "gh --version succeeds" gh --version

# --- gh config file written for vscode user ---
echo "=== /home/vscode/.config/gh/config.yml ==="
cat /home/vscode/.config/gh/config.yml 2> /dev/null || echo "(missing)"

check "gh config.yml exists for vscode user" test -f /home/vscode/.config/gh/config.yml
check "config.yml contains git_protocol: https" bash -c \
  'grep -q "git_protocol: https" /home/vscode/.config/gh/config.yml 2>/dev/null'
check "config.yml owned by vscode" bash -c \
  '[ "$(stat -c %U /home/vscode/.config/gh/config.yml 2>/dev/null)" = "vscode" ]'

reportResults
