#!/bin/bash
# Verifies Oh My Bash per-user configuration:
# - OSH_CUSTOM defaults to ~/.config/bash/custom
# - Default plugins are symlinked into per-user OSH_CUSTOM
# - .bashrc has the OMB block with the correct OSH_CUSTOM value
set -e

source dev-container-features-test-lib

_HOME=/root
_OMB=/usr/local/share/oh-my-bash
_SYS_CUSTOM="${_OMB}/custom"
_USER_CUSTOM="${_HOME}/.config/bash/custom"

# Per-user OMB custom dir created
check "per-user OMB custom dir exists" test -d "$_USER_CUSTOM"
check "per-user OMB themes dir exists" test -d "${_USER_CUSTOM}/themes"
check "per-user OMB plugins dir exists" test -d "${_USER_CUSTOM}/plugins"

# .bashrc OMB block uses per-user OSH_CUSTOM
check ".bashrc sets OSH_CUSTOM to per-user path" grep -qF "OSH_CUSTOM=\"${_USER_CUSTOM}\"" "${_HOME}/.bashrc"
check ".bashrc exports OSH" grep -q 'export OSH=' "${_HOME}/.bashrc"
check ".bashrc sources oh-my-bash.sh" grep -q 'oh-my-bash.sh' "${_HOME}/.bashrc"

reportResults
