#!/bin/bash
# Verifies that a custom font_dir places all four MesloLGS font files at the
# specified path instead of the default /usr/share/fonts/MesloLGS.
set -e

source dev-container-features-test-lib

_FONTS=/opt/fonts/meslo

check "MesloLGS Regular at custom font_dir" test -f "${_FONTS}/MesloLGS NF Regular.ttf"
check "MesloLGS Bold at custom font_dir" test -f "${_FONTS}/MesloLGS NF Bold.ttf"
check "MesloLGS Italic at custom font_dir" test -f "${_FONTS}/MesloLGS NF Italic.ttf"
check "MesloLGS Bold Italic at custom font_dir" test -f "${_FONTS}/MesloLGS NF Bold Italic.ttf"
check "no fonts at default path" bash -c '! test -d /usr/share/fonts/MesloLGS'

reportResults
