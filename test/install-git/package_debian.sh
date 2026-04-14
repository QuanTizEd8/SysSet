#!/bin/bash
# method=package, version=stable on Debian.
# Verifies the Debian package path is used and Ubuntu-only PPA artifacts are
# not written.
set -e

source dev-container-features-test-lib

# --- binary ---
check "git on PATH" command -v git
check "git binary is executable" test -x "$(command -v git)"
check "git is package managed" bash -c 'dpkg -S "$(command -v git)" >/dev/null 2>&1'

# --- functional ---
echo "=== git --version ==="
git --version 2>&1 || echo "(failed)"
check "git --version succeeds" git --version

# --- no PPA on Debian ---
check "no PPA sources.list entry" bash -c '! test -f /etc/apt/sources.list.d/git-core-ppa.list'
check "no PPA keyring" bash -c '! test -f /usr/share/keyrings/git-core-ppa.gpg'

# --- default system gitconfig ---
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is main" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "main" ]'

reportResults
