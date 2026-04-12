#!/bin/bash
# Verifies that PM-specific blocks work on Debian (apt):
# - apt: block → tree and curl installed
# - apk: block → not-a-real-package filtered out (build would fail if attempted)
set -e

source dev-container-features-test-lib

check "tree is installed (apt section selector)" command -v tree
check "curl is installed (apt section selector)" command -v curl
check "apk-only package was not installed" bash -c "! command -v not-a-real-package"

reportResults
