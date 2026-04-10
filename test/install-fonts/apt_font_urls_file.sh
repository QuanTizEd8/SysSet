#!/bin/bash
# Verifies that font_urls with a direct .ttf URL installs the file under a
# namespaced sysset-install-fonts-*/url/<host>/<path>/ directory,
# exercising the individual-file branch.
set -e

source dev-container-features-test-lib

_FONTS=/usr/share/fonts

check "font file installed" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/url/*" -name "JetBrainsMono-Regular.ttf" | grep -q .'
check "no default Meslo directory" bash -c '! test -d /usr/share/fonts/Meslo'

reportResults
