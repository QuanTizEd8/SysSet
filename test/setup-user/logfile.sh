#!/bin/bash
# logfile=/tmp/setup-user.log: all script output is captured to the log file.
set -e

source dev-container-features-test-lib

# --- user account ---
check "vscode user exists"    bash -c 'id vscode > /dev/null 2>&1'

# --- log file ---
check "logfile was created"      test -f /tmp/setup-user.log
check "logfile is non-empty"     test -s /tmp/setup-user.log
check "logfile mentions vscode"  grep -q "vscode" /tmp/setup-user.log

reportResults
