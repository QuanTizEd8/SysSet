#!/bin/bash
# Verifies that the feature installs packages listed in an apt-pkg file
# on a Debian (APT) system.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree

reportResults
