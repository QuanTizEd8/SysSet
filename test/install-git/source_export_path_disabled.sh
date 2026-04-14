#!/bin/bash
# method=source with a custom prefix, export_path="", and symlink=false.
# Verifies git installs successfully without being exposed on PATH.
set -e

source dev-container-features-test-lib

check "git installed at custom prefix" test -x /opt/git/bin/git
check "git version succeeds via explicit path" /opt/git/bin/git --version
check "git is not on PATH" bash -c '! command -v git >/dev/null 2>&1'
check "symlink was not created" bash -c '! test -e /usr/local/bin/git'
check "profile.d export file not written" bash -c '! test -e /etc/profile.d/install-git.sh'
check "bashrc has no install-git PATH marker" bash -c '! grep -Fq "git PATH (install-git)" /etc/bash.bashrc 2>/dev/null'
check "zshenv has no install-git PATH marker" bash -c '! grep -Fq "git PATH (install-git)" /etc/zsh/zshenv 2>/dev/null'

reportResults
