#!/bin/bash
# Verifies that when the dir only contains files for a non-matching ecosystem
# (apk on a Debian/APT host) the feature exits cleanly without installing
# anything.
set -e

source dev-container-features-test-lib

check "feature exited cleanly with no matching ecosystem files" true
check "no packages were installed" bash -c "! command -v tree"

reportResults
