#!/bin/bash
# Verifies that when no manifest is given but install_self=true is explicitly
# set, the feature exits cleanly and installs the system command without error.
set -e

source dev-container-features-test-lib

check "system command exists" test -x /usr/local/bin/install-os-pkg
check "library script exists" test -f /usr/local/lib/install-os-pkg/install.sh

reportResults
