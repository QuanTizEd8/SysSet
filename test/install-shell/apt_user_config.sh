#!/bin/bash
# Verifies that per-user configuration is applied correctly for the root user:
# skel dotfiles are copied to the right locations (ZDOTDIR for zsh files,
# HOME for others), Oh My Zsh guarded block is injected into ZDOTDIR/.zshrc,
# Oh My Bash guarded block is injected into .bashrc, ZDOTDIR is set in
# .zshenv, and per-user custom directories are created with symlinks.
set -e

source dev-container-features-test-lib

_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"
_OMZ_CUSTOM="${_ZDOTDIR}/custom"
_OMB_CUSTOM="${_HOME}/.config/bash/custom"
_OMZ=/usr/local/share/oh-my-zsh

# --- Root dotfiles exist in correct locations ---
check "root .zshenv exists in HOME" test -f "${_HOME}/.zshenv"
check "root .zshrc exists in ZDOTDIR" test -f "${_ZDOTDIR}/.zshrc"
check "root .zprofile exists in ZDOTDIR" test -f "${_ZDOTDIR}/.zprofile"
check "root .zlogin exists in ZDOTDIR" test -f "${_ZDOTDIR}/.zlogin"
check "root .bashrc exists" test -f "${_HOME}/.bashrc"
check "root .shellenv exists" test -f "${_HOME}/.shellenv"
check "root .shellrc exists" test -f "${_HOME}/.shellrc"

# --- ZDOTDIR injected into .zshenv ---
check ".zshenv has ZDOTDIR BEGIN marker" grep -qF '# BEGIN install-shell-zdotdir' "${_HOME}/.zshenv"
check ".zshenv sets ZDOTDIR" grep -q 'ZDOTDIR=' "${_HOME}/.zshenv"
check ".zshenv ZDOTDIR points to .config/zsh" grep -qF "ZDOTDIR=\"${_ZDOTDIR}\"" "${_HOME}/.zshenv"

# --- Oh My Zsh config in zshtheme ---
_ZSHTHEME="${_ZDOTDIR}/zshtheme"
check "zshtheme file written" test -f "$_ZSHTHEME"
check "zshtheme has BEGIN marker" grep -qF '# BEGIN install-shell' "$_ZSHTHEME"
check "zshtheme has END marker" grep -qF '# END install-shell' "$_ZSHTHEME"
check "zshtheme exports ZSH" grep -q 'export ZSH=' "$_ZSHTHEME"
check "zshtheme sets ZSH_CACHE_DIR" grep -qF 'ZSH_CACHE_DIR=' "$_ZSHTHEME"
check "zshtheme sets ZSH_COMPDUMP" grep -qF 'ZSH_COMPDUMP=' "$_ZSHTHEME"
check "zshtheme sets ZSH_CUSTOM to per-user path" grep -qF "ZSH_CUSTOM=\"${_OMZ_CUSTOM}\"" "$_ZSHTHEME"
check "zshtheme disables omz update" grep -qF "zstyle ':omz:update' mode disabled" "$_ZSHTHEME"
check "zshtheme sources oh-my-zsh.sh" grep -q 'oh-my-zsh.sh' "$_ZSHTHEME"
check ".zshrc sources .shellrc" grep -q '\.shellrc' "${_ZDOTDIR}/.zshrc"

# --- Oh My Bash config in bashtheme ---
_BASHTHEME="${_HOME}/.config/bash/bashtheme"
check "bashtheme file written" test -f "$_BASHTHEME"
check "bashtheme sources oh-my-bash.sh" grep -q 'oh-my-bash.sh' "$_BASHTHEME"
check "bashtheme sets OSH_CUSTOM to per-user path" grep -qF "OSH_CUSTOM=\"${_OMB_CUSTOM}\"" "$_BASHTHEME"

# --- Per-user OMZ custom directory with symlinks to system plugins ---
check "ZDOTDIR dir exists" test -d "$_ZDOTDIR"
check "per-user OMZ custom dir exists" test -d "$_OMZ_CUSTOM"
check "per-user OMZ custom themes dir" test -d "${_OMZ_CUSTOM}/themes"
check "per-user OMZ custom plugins dir" test -d "${_OMZ_CUSTOM}/plugins"
check "zsh-syntax-highlighting symlinked into user custom" test -L "${_OMZ_CUSTOM}/plugins/zsh-syntax-highlighting"
check "plugin symlink points to system custom" bash -c "readlink '${_OMZ_CUSTOM}/plugins/zsh-syntax-highlighting' | grep -q '${_OMZ}/custom/plugins/zsh-syntax-highlighting'"

# --- Per-user OMB custom directory ---
check "per-user OMB custom dir exists" test -d "$_OMB_CUSTOM"
check "per-user OMB custom themes dir" test -d "${_OMB_CUSTOM}/themes"
check "per-user OMB custom plugins dir" test -d "${_OMB_CUSTOM}/plugins"

# --- Entire HOME owned by user ---
check "HOME owned by root" bash -c '[ "$(stat -c %U /root)" = "root" ]'
check ".zshrc owned by root" bash -c "[ \"\$(stat -c %U '${_ZDOTDIR}/.zshrc')\" = 'root' ]"
check "ZDOTDIR owned by root" bash -c "[ \"\$(stat -c %U '${_ZDOTDIR}')\" = 'root' ]"

# --- System config files still deployed ---
check "/etc/profile exists" test -f /etc/profile
check "system bashrc exists" bash -c 'test -f /etc/bash.bashrc || test -f /etc/bashrc || test -f /etc/bash/bashrc'

reportResults
