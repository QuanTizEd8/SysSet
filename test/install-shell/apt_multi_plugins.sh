#!/bin/bash
# Verifies that multiple comma-separated plugin slugs are all cloned into the
# correct subdirectories under ZSH_CUSTOM.
set -e

source dev-container-features-test-lib

_CUSTOM=/usr/local/share/oh-my-zsh/custom

check "zsh-autosuggestions cloned" test -d "${_CUSTOM}/plugins/zsh-autosuggestions/.git"
check "zsh-syntax-highlighting cloned" test -d "${_CUSTOM}/plugins/zsh-syntax-highlighting/.git"

reportResults
