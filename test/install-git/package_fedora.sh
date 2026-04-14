#!/bin/bash
# method=package, version=stable on Fedora.
# Verifies the rpm-managed install path and default gitconfig behavior.
set -e

source dev-container-features-test-lib

check "git on PATH" command -v git
check "git binary is executable" test -x "$(command -v git)"
check "git is rpm managed" bash -c 'rpm -qf "$(command -v git)" >/dev/null 2>&1'
check "git --version succeeds" git --version
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is main" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "main" ]'

reportResults
