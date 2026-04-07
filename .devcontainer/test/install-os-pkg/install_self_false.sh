#!/bin/bash
# Verifies that when install_self=false the system command is NOT installed,
# while the requested packages are still installed normally.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree
check "system command is absent" bash -c "! test -x /usr/local/bin/install-os-pkg"
check "library script is absent" bash -c "! test -f /usr/local/lib/install-os-pkg/install.sh"

reportResults
