#!/bin/bash
# Verifies that p10k_fonts=true installs the four MesloLGS NF fonts from
# romkatv/powerlevel10k-media in addition to the default Nerd Fonts.
set -e

source dev-container-features-test-lib

_FONTS=/usr/share/fonts
_P10K_DIR="${_FONTS}/MesloLGS-NF"

check "default Nerd Fonts installed" bash -c 'find '"$_FONTS"' -name "*.ttf" | head -1 | grep -q .'
check "MesloLGS-NF directory exists" test -d "$_P10K_DIR"
check "MesloLGS NF Regular installed" test -f "${_P10K_DIR}/MesloLGS NF Regular.ttf"
check "MesloLGS NF Bold installed" test -f "${_P10K_DIR}/MesloLGS NF Bold.ttf"
check "MesloLGS NF Italic installed" test -f "${_P10K_DIR}/MesloLGS NF Italic.ttf"
check "MesloLGS NF Bold Italic installed" test -f "${_P10K_DIR}/MesloLGS NF Bold Italic.ttf"

reportResults
