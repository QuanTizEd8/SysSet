#!/bin/bash
# Verifies that setting ohmyzsh_theme=romkatv/powerlevel10k installs the p10k
# theme, injects the p10k-specific MesloLGS NF fonts, and configures root's
# .zshrc with the p10k guarded block.
set -e

source dev-container-features-test-lib

_OMZ=/usr/local/share/oh-my-zsh
_CUSTOM="${_OMZ}/custom"

# Theme installation
check "powerlevel10k theme cloned" test -d "${_CUSTOM}/themes/powerlevel10k/.git"
check "powerlevel10k.zsh-theme file present" test -f "${_CUSTOM}/themes/powerlevel10k/powerlevel10k.zsh-theme"

# p10k-specific fonts (MesloLGS NF)
check "MesloLGS Regular font present" bash -c 'find /usr/share/fonts -name "MesloLGS NF Regular.ttf" | grep -q .'
check "MesloLGS Bold font present" bash -c 'find /usr/share/fonts -name "MesloLGS NF Bold.ttf" | grep -q .'

# Root user .zshrc should have the omz guarded block with p10k config
check "root .zshrc exists" test -f /root/.zshrc
check "root .zshrc has OMZ BEGIN marker" grep -qF '# BEGIN install-shell-ohmyzsh' /root/.zshrc
check "root .zshrc has OMZ END marker" grep -qF '# END install-shell-ohmyzsh' /root/.zshrc
check "root .zshrc sets ZSH_THEME to p10k" grep -q 'ZSH_THEME=.*powerlevel10k' /root/.zshrc
check "root .zshrc disables p10k wizard" grep -qF 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' /root/.zshrc
check "root .zshrc sources oh-my-zsh.sh" grep -q 'oh-my-zsh.sh' /root/.zshrc

reportResults
