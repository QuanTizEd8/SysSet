#!/bin/bash
# Verifies that packages in the implicit leading pkg block of a manifest file
# are installed when the 'manifest' option is set to a file path.
set -e

source dev-container-features-test-lib

check "tree is installed (manifest file)" command -v tree
check "curl is installed (manifest file)" command -v curl

reportResults
