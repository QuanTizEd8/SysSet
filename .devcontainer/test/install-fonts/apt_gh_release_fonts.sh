#!/bin/bash
# Verifies that gh_release_fonts downloads and installs all font/archive assets
# from a GitHub release. Uses JetBrains/JetBrainsMono (latest release).
# Fonts are installed under sysset-install-fonts-*/gh/JetBrains/JetBrainsMono/<tag>/<id>/.
set -e

source dev-container-features-test-lib

_FONTS=/usr/share/fonts

check "font files installed from gh" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/gh/JetBrains/JetBrainsMono/*" -name "*.ttf" | grep -q .'
check "no default Meslo directory" bash -c '! test -d /usr/share/fonts/Meslo'

reportResults
