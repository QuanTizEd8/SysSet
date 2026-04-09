#!/bin/bash
# Verifies that gh_release_fonts with an explicit @tag slug hits the
# /releases/tags/<tag> API endpoint and installs fonts into font_dir/<repo>/.
set -e

source dev-container-features-test-lib

check "font directory created" test -d /usr/share/fonts/JetBrainsMono
check "font files present" bash -c 'find /usr/share/fonts/JetBrainsMono -name "*.ttf" | grep -q .'
check "no default Meslo directory" bash -c '! test -d /usr/share/fonts/Meslo'

reportResults
