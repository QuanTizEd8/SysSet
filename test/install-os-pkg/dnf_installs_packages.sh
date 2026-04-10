#!/bin/bash
# Verifies that the feature installs packages listed in a dnf-pkg file
# on a Fedora (DNF) system.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree

reportResults
