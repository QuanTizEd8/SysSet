#!/bin/bash
# Verifies that the feature auto-installs git and ca-certificates when they are
# not pre-installed, then installs all default components successfully.
set -e

source dev-container-features-test-lib

check "git is installed" command -v git
check "curl is installed" command -v curl
check "zsh is installed" command -v zsh
check "oh-my-zsh installed" test -d /usr/local/share/oh-my-zsh
check "oh-my-zsh main script exists" test -f /usr/local/share/oh-my-zsh/oh-my-zsh.sh
check "oh-my-bash installed" test -d /usr/local/share/oh-my-bash
check "starship installed" command -v starship

reportResults
