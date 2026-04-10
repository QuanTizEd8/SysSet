#!/bin/bash
# Verifies that install_ohmyzsh=false, install_ohmybash=false, install_starship=false
# results in a plain zsh install with no framework components.
set -e

source dev-container-features-test-lib

check "zsh is installed" command -v zsh
check "bash is installed" command -v bash
check "oh-my-zsh not installed" bash -c '! test -d /usr/local/share/oh-my-zsh'
check "oh-my-bash not installed" bash -c '! test -d /usr/local/share/oh-my-bash'
check "starship not installed" bash -c '! command -v starship'

reportResults
