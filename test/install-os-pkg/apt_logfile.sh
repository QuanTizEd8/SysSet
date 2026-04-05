#!/bin/bash
# Verifies that when the logfile option is set, a log file is created at the
# specified path and contains installation output.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree
check "logfile was created" test -f /tmp/install-os-pkg.log
check "logfile contains installation output" \
    grep -q "Package installation complete" /tmp/install-os-pkg.log

reportResults
