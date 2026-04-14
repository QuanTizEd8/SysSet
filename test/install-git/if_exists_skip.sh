#!/bin/bash
# if_exists=skip: git is pre-installed in the image (see Dockerfile).
# The installer exits before any post-install side effects, so the original
# package-managed git stays in place and no gitconfig or PATH markers are
# written.
set -e

source dev-container-features-test-lib

# --- original git installation is intact ---
check "git on PATH" command -v git
check "git binary is executable" test -x "$(command -v git)"
check "git is still package managed" bash -c 'dpkg -S "$(command -v git)" >/dev/null 2>&1'
echo "=== git --version ==="
git --version 2>&1 || echo "(failed)"
check "git --version succeeds" git --version

# --- installation was skipped: verify git is still the pre-installed version ---
check "git is still functional" bash -c 'git --version | grep -qE "^git version [0-9]"'
check "skip did not write /etc/gitconfig" bash -c '! test -e /etc/gitconfig'
check "skip did not write /etc/profile.d/install-git.sh" bash -c '! test -e /etc/profile.d/install-git.sh'

reportResults
