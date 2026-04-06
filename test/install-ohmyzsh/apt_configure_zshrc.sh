#!/bin/bash
# Verifies that configure_zshrc_for=root writes a guarded oh-my-zsh block
# to /root/.zshrc that exports ZSH and ZSH_CUSTOM and sources oh-my-zsh.sh.
set -e

source dev-container-features-test-lib

check "root .zshrc exists" test -f /root/.zshrc
check ".zshrc has BEGIN marker" grep -qF "# BEGIN install-ohmyzsh" /root/.zshrc
check ".zshrc has END marker" grep -qF "# END install-ohmyzsh" /root/.zshrc
check ".zshrc exports ZSH" grep -q 'export ZSH=' /root/.zshrc
check ".zshrc exports ZSH_CUSTOM" grep -q 'export ZSH_CUSTOM=' /root/.zshrc
check ".zshrc sources oh-my-zsh.sh" grep -q 'oh-my-zsh.sh' /root/.zshrc
check ".zshrc ZSH_THEME uses dir/file format" grep -qE 'ZSH_THEME="[^/]+/[^/]+"' /root/.zshrc
check ".zshrc sources .p10k.zsh if present" grep -qF '.p10k.zsh' /root/.zshrc
check "root .zprofile exists" test -f /root/.zprofile
check ".zprofile sources .profile" grep -q '\.profile' /root/.zprofile

reportResults
