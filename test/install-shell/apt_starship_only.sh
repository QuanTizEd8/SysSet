#!/bin/bash
# Verifies that installing only Starship (no OMZ/OMB/fonts) works and that the
# starship binary is functional.
set -e

source dev-container-features-test-lib

check "starship binary installed" command -v starship
check "starship responds to --version" starship --version
check "oh-my-zsh not installed" bash -c '! test -d /usr/local/share/oh-my-zsh'
check "oh-my-bash not installed" bash -c '! test -d /usr/local/share/oh-my-bash'

reportResults
