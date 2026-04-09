#!/bin/bash
# Verifies that font_urls installs a font archive from a direct URL under a
# namespaced sysset-install-fonts-*/url/<host>/<path>/ subdirectory.
set -e

source dev-container-features-test-lib

_FONTS=/usr/share/fonts

check "font files installed from url" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/url/*" -name "*.ttf" | grep -q .'
check "fonts under url namespace" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/url/*" | grep -q .'
check "no default Meslo directory" bash -c '! test -d /usr/share/fonts/Meslo'

reportResults
