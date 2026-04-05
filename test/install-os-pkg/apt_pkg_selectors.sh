#!/bin/bash
# Verifies that pkg file selector syntax works:
# - "tree [pm=apt]" and "curl [pm=apt, id=debian]" are installed
# - "not-a-real-package [pm=apk]" is filtered out (build would fail if attempted)
set -e

source dev-container-features-test-lib

check "tree is installed (pm=apt selector)" command -v tree
check "curl is installed (pm=apt,id=debian selector)" command -v curl
check "apk-only package was not installed" bash -c "! command -v not-a-real-package"

reportResults
