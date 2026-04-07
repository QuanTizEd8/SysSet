#!/bin/bash
# Verifies that installing only zsh (no frameworks, no fonts) works correctly.
set -e

source dev-container-features-test-lib

check "zsh is installed" command -v zsh
check "oh-my-zsh not installed" bash -c '! test -d /usr/local/share/oh-my-zsh'
check "oh-my-bash not installed" bash -c '! test -d /usr/local/share/oh-my-bash'
check "starship not installed" bash -c '! command -v starship'
check "no nerd fonts installed" bash -c '! find /usr/share/fonts -name "*Nerd*" -o -name "MesloLGS*" 2>/dev/null | grep -q .'

# System config files should still be deployed
check "/etc/profile exists" test -f /etc/profile
check "system bashrc exists" bash -c 'test -f /etc/bash.bashrc || test -f /etc/bashrc || test -f /etc/bash/bashrc'

reportResults
