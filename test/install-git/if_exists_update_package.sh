#!/bin/bash
# if_exists=update with preinstalled package git.
# Verifies the installer does not short-circuit to skip and still applies
# post-install gitconfig writes.
set -e

source dev-container-features-test-lib

check "git on PATH" command -v git
check "git is still package managed" bash -c 'dpkg -S "$(command -v git)" >/dev/null 2>&1'
check "git --version succeeds" git --version
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is trunk" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "trunk" ]'

reportResults
