#!/bin/bash
# Verifies that font_urls with a direct .ttf URL installs the file flat in
# font_dir (no subdirectory), exercising the individual-file branch.
set -e

source dev-container-features-test-lib

check "font file installed flat" test -f /usr/share/fonts/JetBrainsMono-Regular.ttf
check "no subdirectory created" bash -c '! test -d /usr/share/fonts/JetBrainsMono-Regular'
check "no default Meslo directory" bash -c '! test -d /usr/share/fonts/Meslo'

reportResults
