#!/bin/bash
# Verifies that the feature installs packages listed in a pacman-pkg file
# on an Arch Linux (Pacman) system.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree

reportResults
