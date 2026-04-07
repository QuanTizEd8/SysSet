#!/bin/bash
# Verifies that custom install directories are respected for both Oh My Zsh
# and Oh My Bash, and that the default paths are NOT populated.
set -e

source dev-container-features-test-lib

_OMZ=/opt/oh-my-zsh
_OMB=/opt/oh-my-bash

# Custom paths exist
check "oh-my-zsh at custom path" test -d "$_OMZ"
check "oh-my-zsh main script at custom path" test -f "${_OMZ}/oh-my-zsh.sh"
check "oh-my-bash at custom path" test -d "$_OMB"
check "oh-my-bash main script at custom path" test -f "${_OMB}/oh-my-bash.sh"

# Default paths NOT populated
check "omz not at default path" bash -c '! test -d /usr/local/share/oh-my-zsh'
check "omb not at default path" bash -c '! test -d /usr/local/share/oh-my-bash'

# Root user configured (add_root_user_config=true)
check "root .zshrc exists" test -f /root/.zshrc
check "root .bashrc exists" test -f /root/.bashrc

reportResults
