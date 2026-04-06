#!/bin/bash
# Verifies that the feature installs Oh My Zsh successfully even when git is
# not present on the base image.  The feature must auto-install git before
# attempting to clone any repositories.
set -e

source dev-container-features-test-lib

check "git was auto-installed" command -v git
check "oh-my-zsh install dir exists" test -d /usr/local/share/oh-my-zsh
check "oh-my-zsh main script exists" test -f /usr/local/share/oh-my-zsh/oh-my-zsh.sh

reportResults
