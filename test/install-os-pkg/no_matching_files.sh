#!/bin/bash
# Verifies that when the manifest contains only sections for a non-matching
# ecosystem (apk-specific packages on a Debian/APT host) the feature exits cleanly without
# installing anything.
set -e

source dev-container-features-test-lib

check "feature exited cleanly with no matching manifest sections" true
check "no packages were installed" bash -c "! command -v tree"

reportResults
