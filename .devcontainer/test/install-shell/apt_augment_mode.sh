#!/bin/bash
# Verifies that user_config_mode=augment does not overwrite files that already
# exist, but still injects framework blocks and creates missing resources.
# The scenario Dockerfile pre-creates a custom .zshrc / .bashrc so we can
# confirm their content is preserved.
set -e

source dev-container-features-test-lib

_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"

# Pre-existing files were preserved (content injected by Dockerfile)
check "pre-existing ZDOTDIR/.zshrc preserved" grep -qF 'MY_CUSTOM_LINE' "${_ZDOTDIR}/.zshrc"

# Framework blocks are still injected even in augment mode
check "OMZ block injected despite existing .zshrc" grep -qF '# BEGIN install-shell-ohmyzsh' "${_ZDOTDIR}/.zshrc"
check "OMB block injected despite existing .bashrc" grep -qF '# BEGIN install-shell-ohmybash' "${_HOME}/.bashrc"

# ZDOTDIR block in .zshenv
check "ZDOTDIR block injected into .zshenv" grep -qF '# BEGIN install-shell-zdotdir' "${_HOME}/.zshenv"

# Per-user custom dirs created
check "per-user OMZ custom dir created" test -d "${_ZDOTDIR}/custom"
check "per-user OMB custom dir created" test -d "${_HOME}/.config/bash/custom"

reportResults
