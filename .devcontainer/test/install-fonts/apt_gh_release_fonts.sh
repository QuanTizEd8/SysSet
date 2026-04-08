#!/bin/bash
# Verifies that gh_release_fonts downloads and installs all font/archive assets
# from a GitHub release. Uses JetBrains/JetBrainsMono (latest release).
# Fonts are installed into font_dir/<repo-name>/.
set -e

source dev-container-features-test-lib

check "font directory created" test -d /usr/share/fonts/JetBrainsMono
check "font files present" bash -c 'find /usr/share/fonts/JetBrainsMono -name "*.ttf" | grep -q .'
check "no default Meslo directory" bash -c '! test -d /usr/share/fonts/Meslo'

reportResults
