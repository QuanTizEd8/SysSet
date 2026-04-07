#!/bin/bash
# Verifies that all four manifest section types are executed:
#   prescript  → runs before install (creates /tmp/prescript-ran)
#   pkg        → installs tree
#   script     → runs after install (creates /tmp/script-ran)
set -e

source dev-container-features-test-lib

check "prescript ran" test -f /tmp/prescript-ran
check "tree is installed (pkg section)" command -v tree
check "script ran" test -f /tmp/script-ran

reportResults
