#!/bin/bash
# Verifies that manifest file works on Alpine (apk):
# - apt: block is filtered out
# - apk: block → tree installed
set -e

source dev-container-features-test-lib

check "tree is installed (apk manifest section)" command -v tree
check "apt-only package was not installed" bash -c "! command -v not-a-real-package"

reportResults
