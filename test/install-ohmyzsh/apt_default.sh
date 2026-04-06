#!/bin/bash
# Verifies the default installation: oh-my-zsh core, powerlevel10k theme,
# zsh-syntax-highlighting plugin, and MesloLGS Nerd Fonts all present.
set -e

source dev-container-features-test-lib

check "oh-my-zsh install dir exists" test -d /usr/local/share/oh-my-zsh
check "oh-my-zsh main script exists" test -f /usr/local/share/oh-my-zsh/oh-my-zsh.sh
check "powerlevel10k theme cloned" test -d /usr/local/share/oh-my-zsh/custom/themes/powerlevel10k/.git
check "zsh-syntax-highlighting plugin cloned" test -d /usr/local/share/oh-my-zsh/custom/plugins/zsh-syntax-highlighting/.git
check "MesloLGS Regular font present" test -f "/usr/share/fonts/MesloLGS/MesloLGS NF Regular.ttf"
check "MesloLGS Bold font present" test -f "/usr/share/fonts/MesloLGS/MesloLGS NF Bold.ttf"

reportResults
