#!/bin/bash
# Verifies that multiple comma-separated plugin slugs are all cloned into the
# correct subdirectories, and that the plugins() line in .zshrc lists every
# plugin name.
set -e

source dev-container-features-test-lib

_CUSTOM=/usr/local/share/oh-my-zsh/custom

check "zsh-autosuggestions cloned" test -d "${_CUSTOM}/plugins/zsh-autosuggestions/.git"
check "zsh-syntax-highlighting cloned" test -d "${_CUSTOM}/plugins/zsh-syntax-highlighting/.git"
check "root .zshrc has plugins() line" grep -qF 'plugins=(' /root/.zshrc
check "root .zshrc lists zsh-autosuggestions" grep -q 'zsh-autosuggestions' /root/.zshrc
check "root .zshrc lists zsh-syntax-highlighting" grep -q 'zsh-syntax-highlighting' /root/.zshrc

reportResults
