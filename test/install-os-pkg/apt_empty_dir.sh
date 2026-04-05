#!/bin/bash
# Verifies that when the manifest contains no packages the feature exits
# cleanly (build succeeds) without installing anything.
set -e

source dev-container-features-test-lib

check "feature exited cleanly with empty manifest" true
check "no packages were installed" bash -c "! command -v tree"

reportResults
