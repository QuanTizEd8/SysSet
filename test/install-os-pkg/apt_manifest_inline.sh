#!/bin/bash
# Verifies that an inline manifest (MANIFEST env var contains a newline) installs
# packages from the implicit leading pkg block.
set -e

source dev-container-features-test-lib

check "tree is installed (inline manifest)" command -v tree
check "curl is installed (inline manifest)" command -v curl

reportResults
