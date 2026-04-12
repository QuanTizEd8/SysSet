#!/bin/bash
# Verifies that PM and OS when clauses work on Debian (apt):
# - tree (when: {pm: apt}) and curl (when: {pm: apt, id: debian}) are installed
# - not-a-real-package (when: {pm: apk}) is filtered out (build would fail if attempted)
set -e

source dev-container-features-test-lib

check "tree is installed (when: {pm: apt})" command -v tree
check "curl is installed (when: {pm: apt, id: debian})" command -v curl
check "apk-only package was not installed" bash -c "! command -v not-a-real-package"

reportResults
