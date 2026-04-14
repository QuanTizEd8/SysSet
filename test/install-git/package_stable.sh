#!/bin/bash
# method=package, version=stable on Ubuntu.
# Verifies version=stable skips the PPA and that source-only options are
# ignored instead of creating source-build artifacts.
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

# --- no PPA (version=stable bypasses PPA even on Ubuntu) ---
check "no PPA sources.list entry" bash -c '! test -f /etc/apt/sources.list.d/git-core-ppa.list'

# --- source-only options were ignored ---
check "custom source prefix was not created" bash -c '! test -e /opt/git/bin/git'
check "custom export_path file was not created" bash -c '! test -e /tmp/install-git-path.sh'
check "source symlink was not created" bash -c '! test -L /usr/local/bin/git'

# --- default system gitconfig ---
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is main" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "main" ]'

reportResults
