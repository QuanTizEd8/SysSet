#!/bin/bash
# Verifies the default installation: Meslo and JetBrainsMono Nerd Fonts
# installed to /usr/share/fonts.
set -e

source dev-container-features-test-lib

_FONTS=/usr/share/fonts

check "font directory exists" test -d "$_FONTS"
check "at least one font file installed" bash -c 'find '"$_FONTS"' -name "*.ttf" -o -name "*.otf" | head -1 | grep -q .'
check "Meslo fonts installed" test -d "${_FONTS}/Meslo"
check "JetBrainsMono fonts installed" test -d "${_FONTS}/JetBrainsMono"
check "font cache refreshed" bash -c 'fc-list | grep -qi "meslo\|jetbrains"'

reportResults
