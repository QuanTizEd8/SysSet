#!/bin/bash
# Verifies that when install_self=false the system command wrapper is NOT
# installed, while packages and the backing library are still set up normally.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree
check "system command wrapper is absent" bash -c "! test -x /usr/local/bin/install-os-pkg"
check "library script is present (always installed)" test -f /usr/local/lib/install-os-pkg/install.sh

reportResults
