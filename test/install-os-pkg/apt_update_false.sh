#!/bin/bash
# Verifies that the feature can install packages when update=false, relying
# on package lists that were already refreshed in the base image layer.
set -e

source dev-container-features-test-lib

check "tree is installed without re-running apt-get update" command -v tree

reportResults
