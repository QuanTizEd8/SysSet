#!/bin/bash
# Verifies that when no_clean=true the feature skips cache cleanup, leaving
# /var/lib/apt/lists/ populated after the run.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree
check "apt package lists are preserved" \
    bash -c "ls /var/lib/apt/lists/ | grep -q ."

reportResults
