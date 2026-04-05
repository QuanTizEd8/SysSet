#!/bin/bash
# Verifies that the feature installs packages listed in a zypper-pkg file
# on an openSUSE (Zypper) system.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree

reportResults
