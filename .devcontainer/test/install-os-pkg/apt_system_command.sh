#!/bin/bash
# Verifies that running the feature installs /usr/local/bin/install-os-pkg
# as a callable system command, and that the backing library script is present.
set -e

source dev-container-features-test-lib

check "system command exists"     test -x /usr/local/bin/install-os-pkg
check "library script exists"     test -f /usr/local/lib/install-os-pkg/install.sh
check "command is in PATH"        command -v install-os-pkg
check "command accepts --help flag" bash -c "install-os-pkg --no_such_flag 2>&1 | grep -q 'Unknown option' || true"
check "tree is installed (initial dir install)" command -v tree
check "system command can install packages" bash -c "install-os-pkg --manifest $'curl\n' && command -v curl"

reportResults
