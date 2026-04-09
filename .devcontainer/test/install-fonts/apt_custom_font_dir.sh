#!/bin/bash
# Verifies that a custom font_dir places fonts at the specified path instead
# of the default /usr/share/fonts.
set -e

source dev-container-features-test-lib

_FONT_DIR=/opt/fonts

check "custom font directory exists" test -d "$_FONT_DIR"
check "at least one font file at custom path" bash -c 'find '"$_FONT_DIR"' -name "*.ttf" -o -name "*.otf" | head -1 | grep -q .'
check "no Meslo at default path" bash -c '! test -d /usr/share/fonts/Meslo'
check "no JetBrainsMono at default path" bash -c '! test -d /usr/share/fonts/JetBrainsMono'

reportResults
