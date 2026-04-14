#!/bin/bash
# method=package (default), version=latest on a supported Ubuntu release.
# Verifies the PPA path is actually taken and the package-managed git binary
# remains functional with the default system gitconfig applied.
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
check "git version is at least 2" bash -c '[ "$(git --version | awk "{print \$3}" | cut -d. -f1)" -ge 2 ]'

# --- PPA path ---
check "PPA sources.list.d entry created" test -f /etc/apt/sources.list.d/git-core-ppa.list
check "PPA keyring created" test -f /usr/share/keyrings/git-core-ppa.gpg
check "PPA signed-by annotation present" grep -Fq "signed-by=/usr/share/keyrings/git-core-ppa.gpg" /etc/apt/sources.list.d/git-core-ppa.list
check "PPA entry targets noble" grep -Fq 'https://ppa.launchpadcontent.net/git-core/ppa/ubuntu noble main' /etc/apt/sources.list.d/git-core-ppa.list

# --- default system gitconfig (default_branch=main by default) ---
echo "=== /etc/gitconfig ==="
cat /etc/gitconfig 2> /dev/null || echo "(missing)"
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is main" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "main" ]'

reportResults
