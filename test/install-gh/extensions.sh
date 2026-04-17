#!/bin/bash
# extensions="github/gh-copilot" with add_remote_user=true (vscode user).
# Verifies that the extensions option is parsed and that _gh__install_extensions
# is invoked, confirmed by the "Installing gh extension" line in the install log.
# (The actual extension install is non-fatal; we assert the attempt was made.)
set -e

source dev-container-features-test-lib

# --- gh installed ---
check "gh on PATH" command -v gh
check "gh --version succeeds" gh --version

# --- extension install was attempted ---
echo "===== /tmp/gh-ext-install.log (last 20 lines) ====="
tail -n 20 /tmp/gh-ext-install.log 2> /dev/null || echo "(logfile missing)"

check "install logfile was created" test -f /tmp/gh-ext-install.log
check "extension install was attempted for vscode" bash -c \
  "grep -q \"Installing gh extension 'github/gh-copilot' for user 'vscode'\" \
   /tmp/gh-ext-install.log 2>/dev/null"

reportResults
