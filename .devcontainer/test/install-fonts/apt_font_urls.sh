#!/bin/bash
# Verifies that font_urls installs a font archive from a direct URL.
# Uses NerdFontsSymbolsOnly.tar.xz which extracts into a named subdirectory.
set -e

source dev-container-features-test-lib

check "font directory created" test -d /usr/share/fonts/NerdFontsSymbolsOnly
check "font files present" bash -c 'find /usr/share/fonts/NerdFontsSymbolsOnly -name "*.ttf" | grep -q .'
check "no default Meslo directory" bash -c '! test -d /usr/share/fonts/Meslo'

reportResults
