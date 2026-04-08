#!/bin/bash
# Verifies that setting ohmyzsh_theme=romkatv/powerlevel10k installs the p10k
# theme, injects the p10k-specific MesloLGS NF fonts, and configures root's
# ZDOTDIR/.zshrc with the p10k guarded block and correct ZSH_CUSTOM.
set -e

source dev-container-features-test-lib

_OMZ=/usr/local/share/oh-my-zsh
_CUSTOM="${_OMZ}/custom"
_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"
_USER_CUSTOM="${_ZDOTDIR}/custom"

# Theme installation in system custom dir
check "powerlevel10k theme cloned" test -d "${_CUSTOM}/themes/powerlevel10k/.git"
check "powerlevel10k.zsh-theme file present" test -f "${_CUSTOM}/themes/powerlevel10k/powerlevel10k.zsh-theme"

# p10k-specific fonts (MesloLGS NF)
check "MesloLGS Regular font present" bash -c 'find /usr/share/fonts -name "MesloLGS NF Regular.ttf" | grep -q .'
check "MesloLGS Bold font present" bash -c 'find /usr/share/fonts -name "MesloLGS NF Bold.ttf" | grep -q .'

# Root user .zshrc in ZDOTDIR should have the omz guarded block
check "ZDOTDIR/.zshrc exists" test -f "${_ZDOTDIR}/.zshrc"
check ".zshrc has OMZ BEGIN marker" grep -qF '# BEGIN install-shell-ohmyzsh' "${_ZDOTDIR}/.zshrc"
check ".zshrc has OMZ END marker" grep -qF '# END install-shell-ohmyzsh' "${_ZDOTDIR}/.zshrc"
check ".zshrc sets ZSH_THEME to p10k" grep -q 'ZSH_THEME=.*powerlevel10k' "${_ZDOTDIR}/.zshrc"
check ".zshrc disables p10k wizard" grep -qF 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' "${_ZDOTDIR}/.zshrc"
check ".zshrc sources oh-my-zsh.sh" grep -q 'oh-my-zsh.sh' "${_ZDOTDIR}/.zshrc"
check ".zshrc sources .p10k.zsh" grep -q 'p10k.zsh' "${_ZDOTDIR}/.zshrc"

# ZSH_CUSTOM points to per-user dir
check ".zshrc sets ZSH_CUSTOM to per-user path" grep -qF "ZSH_CUSTOM=\"${_USER_CUSTOM}\"" "${_ZDOTDIR}/.zshrc"

# Per-user custom dir has symlink to system p10k theme
check "p10k symlink in user custom themes" test -L "${_USER_CUSTOM}/themes/powerlevel10k"
check "p10k symlink target is system custom" bash -c "readlink '${_USER_CUSTOM}/themes/powerlevel10k' | grep -qF '${_CUSTOM}/themes/powerlevel10k'"

# p10k config deployed
check "root .p10k.zsh exists" test -f "${_HOME}/.p10k.zsh"

reportResults
