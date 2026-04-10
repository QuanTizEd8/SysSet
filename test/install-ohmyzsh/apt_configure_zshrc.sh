#!/bin/bash
# Verifies that configure_zshrc=true writes a guarded oh-my-zsh block
# to /etc/zsh/zshrc that exports ZSH and ZSH_CUSTOM and sources oh-my-zsh.sh.
set -e

source dev-container-features-test-lib

check "/etc/zsh/zshrc exists" test -f /etc/zsh/zshrc
check "zshrc has BEGIN marker" grep -qF "# BEGIN install-ohmyzsh" /etc/zsh/zshrc
check "zshrc has END marker" grep -qF "# END install-ohmyzsh" /etc/zsh/zshrc
check "zshrc exports ZSH" grep -q 'export ZSH=' /etc/zsh/zshrc
check "zshrc exports ZSH_CUSTOM" grep -q 'export ZSH_CUSTOM=' /etc/zsh/zshrc
check "zshrc sources oh-my-zsh.sh" grep -q 'oh-my-zsh.sh' /etc/zsh/zshrc
check "zshrc ZSH_THEME uses dir/file format" grep -qE 'ZSH_THEME="[^/]+/[^/]+"' /etc/zsh/zshrc
check "zshrc sources .p10k.zsh if present" grep -qF '.p10k.zsh' /etc/zsh/zshrc
check "/etc/zsh/zprofile exists" test -f /etc/zsh/zprofile
check "zprofile sources .profile" grep -q '\.profile' /etc/zsh/zprofile

reportResults
