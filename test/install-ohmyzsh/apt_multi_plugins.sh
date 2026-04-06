#!/bin/bash
# Verifies that multiple comma-separated plugin slugs are all cloned into the
# correct subdirectories, and that the plugins() line in /etc/zsh/zshrc lists
# every plugin name.
set -e

source dev-container-features-test-lib

_CUSTOM=/usr/local/share/oh-my-zsh/custom

check "zsh-autosuggestions cloned" test -d "${_CUSTOM}/plugins/zsh-autosuggestions/.git"
check "zsh-syntax-highlighting cloned" test -d "${_CUSTOM}/plugins/zsh-syntax-highlighting/.git"
check "/etc/zsh/zshrc has plugins() line" grep -qF 'plugins=(' /etc/zsh/zshrc
check "/etc/zsh/zshrc lists zsh-autosuggestions" grep -q 'zsh-autosuggestions' /etc/zsh/zshrc
check "/etc/zsh/zshrc lists zsh-syntax-highlighting" grep -q 'zsh-syntax-highlighting' /etc/zsh/zshrc

reportResults
