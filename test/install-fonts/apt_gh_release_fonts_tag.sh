#!/bin/bash
# Verifies that gh_release_fonts with an explicit @tag slug hits the
# /releases/tags/<tag> API endpoint and installs fonts under
# sysset-install-fonts-*/gh/<owner>/<repo>/<tag>/<id>/.
set -e

source dev-container-features-test-lib

_FONTS=/usr/share/fonts

check "font files installed from gh tag" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/gh/JetBrains/JetBrainsMono/*" -name "*.ttf" | grep -q .'
check "no default Meslo directory" bash -c '! test -d /usr/share/fonts/Meslo'

reportResults
