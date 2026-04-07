#!/bin/bash
# Verifies that install_fonts=false skips all font downloads while frameworks
# still install correctly.
set -e

source dev-container-features-test-lib

check "oh-my-zsh installed" test -d /usr/local/share/oh-my-zsh
check "oh-my-bash installed" test -d /usr/local/share/oh-my-bash
check "starship installed" command -v starship
check "no nerd fonts installed" bash -c '! find /usr/share/fonts -name "*Nerd*" -o -name "MesloLGS*" 2>/dev/null | grep -q .'

reportResults
