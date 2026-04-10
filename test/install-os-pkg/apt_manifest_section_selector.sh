#!/bin/bash
# Verifies that manifest section selectors work:
# - "--- pkg [pm=apt]" section → tree and curl installed
# - "--- pkg [pm=apk]" section → not-a-real-package filtered out (build would fail if attempted)
set -e

source dev-container-features-test-lib

check "tree is installed (apt section selector)" command -v tree
check "curl is installed (apt section selector)" command -v curl
check "apk-only package was not installed" bash -c "! command -v not-a-real-package"

reportResults
