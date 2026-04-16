#!/bin/bash
# Verifies that the feature can install packages on Alpine when update=false,
# relying on the package index refreshed in the base image layer.
set -e

source dev-container-features-test-lib

check "tree is installed without re-running apk update" command -v tree

reportResults
