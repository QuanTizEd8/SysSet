#!/bin/bash
# Verifies that apt-prescript runs before package install and apt-script runs
# after, each leaving a marker file, and that the target package is installed.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree
check "prescript was executed" test -f /tmp/markers/prescript-ran
check "postscript was executed" test -f /tmp/markers/script-ran

reportResults
