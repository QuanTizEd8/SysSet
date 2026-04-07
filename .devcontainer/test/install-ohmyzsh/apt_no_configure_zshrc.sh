#!/bin/bash
# Verifies that configure_zshrc=false skips writing /etc/zsh/zshrc entirely.
set -e

source dev-container-features-test-lib

check "global zshrc not written" bash -c '! grep -qF "# BEGIN install-ohmyzsh" /etc/zsh/zshrc 2>/dev/null'
check "oh-my-zsh still installed" test -f /usr/local/share/oh-my-zsh/oh-my-zsh.sh

reportResults
