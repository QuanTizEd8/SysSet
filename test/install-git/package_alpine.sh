#!/bin/bash
# method=package, version=stable on Alpine.
# Verifies the Alpine package path and default gitconfig behavior.
set -e

source dev-container-features-test-lib

check "git on PATH" command -v git
check "git binary is executable" test -x "$(command -v git)"
check "git package is installed" apk info -e git
check "git --version succeeds" git --version
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is main" sh -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "main" ]'

reportResults
