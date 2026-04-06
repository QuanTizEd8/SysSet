#!/bin/bash
# Verifies that lists_max_age=0 forces a package list update (never skips) and
# that packages are successfully installed afterwards.  The Dockerfile
# intentionally does NOT run apt-get update in advance, so the feature must
# update before installing.
set -e

source dev-container-features-test-lib

check "tree is installed (lists_max_age=0 forced update)" command -v tree

reportResults
