#!/bin/bash
# Verifies that when the dir contains no apt-* files the feature exits
# cleanly (build succeeds) without installing anything.
set -e

source dev-container-features-test-lib

check "feature exited cleanly with empty dir" true
check "no packages were installed" bash -c "! command -v tree"

reportResults
