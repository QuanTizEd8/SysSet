#!/bin/bash
# Verifies that setting install_fonts=false skips font download entirely while
# oh-my-zsh itself still installs correctly.
set -e

source dev-container-features-test-lib

check "oh-my-zsh install dir exists" test -d /usr/local/share/oh-my-zsh
check "oh-my-zsh main script exists" test -f /usr/local/share/oh-my-zsh/oh-my-zsh.sh
check "powerlevel10k theme cloned" test -d /usr/local/share/oh-my-zsh/custom/themes/powerlevel10k/.git
check "no font files installed" bash -c '! ls "/usr/share/fonts/MesloLGS/"*.ttf 2>/dev/null | grep -q .'

reportResults
