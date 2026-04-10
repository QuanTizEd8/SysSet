#!/bin/bash
# Verifies that nerd_fonts="" skips all Nerd Font downloads without error.
# The script should complete successfully and leave no font files behind.
set -e

source dev-container-features-test-lib

check "no Meslo directory" bash -c '! test -d /usr/share/fonts/Meslo'
check "no JetBrainsMono directory" bash -c '! test -d /usr/share/fonts/JetBrainsMono'

reportResults
