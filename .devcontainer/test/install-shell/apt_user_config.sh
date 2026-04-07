#!/bin/bash
# Verifies that per-user configuration is applied correctly for the root user:
# skel dotfiles are copied, Oh My Zsh guarded block is injected into .zshrc,
# Oh My Bash guarded block is injected into .bashrc, and per-user custom
# directories are created.
set -e

source dev-container-features-test-lib

# --- Root dotfiles exist ---
check "root .zshrc exists" test -f /root/.zshrc
check "root .bashrc exists" test -f /root/.bashrc
check "root .shellenv exists" test -f /root/.shellenv
check "root .shellrc exists" test -f /root/.shellrc

# --- Oh My Zsh guarded block in .zshrc ---
check ".zshrc has OMZ BEGIN marker" grep -qF '# BEGIN install-shell-ohmyzsh' /root/.zshrc
check ".zshrc has OMZ END marker" grep -qF '# END install-shell-ohmyzsh' /root/.zshrc
check ".zshrc exports ZSH" grep -q 'export ZSH=' /root/.zshrc
check ".zshrc sets ZSH_CACHE_DIR" grep -qF 'ZSH_CACHE_DIR=' /root/.zshrc
check ".zshrc sets ZSH_COMPDUMP" grep -qF 'ZSH_COMPDUMP=' /root/.zshrc
check ".zshrc sets ZSH_CUSTOM" grep -qF 'ZSH_CUSTOM=' /root/.zshrc
check ".zshrc disables omz update" grep -qF "zstyle ':omz:update' mode disabled" /root/.zshrc
check ".zshrc sources oh-my-zsh.sh" grep -q 'oh-my-zsh.sh' /root/.zshrc
check ".zshrc also sources .shellrc" grep -q '\.shellrc' /root/.zshrc

# --- Oh My Bash guarded block in .bashrc ---
check ".bashrc has OMB BEGIN marker" grep -qF '# BEGIN install-shell-ohmybash' /root/.bashrc
check ".bashrc has OMB END marker" grep -qF '# END install-shell-ohmybash' /root/.bashrc
check ".bashrc sources oh-my-bash.sh" grep -q 'oh-my-bash.sh' /root/.bashrc

# --- Per-user custom directories ---
check "per-user OMZ custom dir exists" test -d /root/.oh-my-zsh-custom
check "per-user OMZ custom themes dir" test -d /root/.oh-my-zsh-custom/themes
check "per-user OMZ custom plugins dir" test -d /root/.oh-my-zsh-custom/plugins

# --- System config files still deployed ---
check "/etc/profile exists" test -f /etc/profile
check "system bashrc exists" bash -c 'test -f /etc/bash.bashrc || test -f /etc/bashrc || test -f /etc/bash/bashrc'

reportResults
