#!/bin/bash
# Verifies that a custom font_dir places fonts at the specified path instead
# of the default /usr/share/fonts.
set -e

source dev-container-features-test-lib

_FONT_DIR=/opt/fonts

check "custom font directory exists" test -d "$_FONT_DIR"
check "at least one font file at custom path" bash -c 'find '"$_FONT_DIR"' -name "*.ttf" -o -name "*.otf" | head -1 | grep -q .'
check "no fonts at default path" bash -c '! find /usr/share/fonts -path "*/sysset-install-fonts-*" 2>/dev/null | grep -q .'

reportResults
