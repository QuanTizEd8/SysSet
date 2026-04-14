#!/bin/bash
# logfile option: install log is appended to /tmp/git.log.
# Verifies the log contains recognizable installer lifecycle markers.
set -e

source dev-container-features-test-lib

# --- binary ---
check "git on PATH" command -v git
check "git --version succeeds" git --version

# --- logfile ---
echo "=== /tmp/git.log (first 10 lines) ==="
head -10 /tmp/git.log 2> /dev/null || echo "(missing)"

check "logfile exists" test -f /tmp/git.log
check "logfile is non-empty" test -s /tmp/git.log
check "logfile contains script entry" grep -Fq 'Script entry: Git Installation Devcontainer Feature Installer' /tmp/git.log
check "logfile contains script exit" grep -Fq 'Script exit: Git Installation Devcontainer Feature Installer' /tmp/git.log

reportResults
