#!/bin/bash
# Verifies that p10k_fonts=true installs the four MesloLGS NF fonts from
# romkatv/powerlevel10k-media in addition to the default Nerd Fonts.
set -e

source dev-container-features-test-lib

_FONTS=/usr/share/fonts

check "default Nerd Fonts installed" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/nerd/*" -name "*.ttf" | head -1 | grep -q .'
check "MesloLGS-NF directory exists" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/p10k/MesloLGS-NF" -type d | grep -q .'
check "MesloLGS NF Regular installed" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/p10k/MesloLGS-NF/MesloLGS NF Regular.ttf" | grep -q .'
check "MesloLGS NF Bold installed" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/p10k/MesloLGS-NF/MesloLGS NF Bold.ttf" | grep -q .'
check "MesloLGS NF Italic installed" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/p10k/MesloLGS-NF/MesloLGS NF Italic.ttf" | grep -q .'
check "MesloLGS NF Bold Italic installed" bash -c 'find '"$_FONTS"' -path "*/sysset-install-fonts-*/p10k/MesloLGS-NF/MesloLGS NF Bold Italic.ttf" | grep -q .'

reportResults
