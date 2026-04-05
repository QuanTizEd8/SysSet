#!/bin/bash
# Verifies that the feature installs packages listed in an apk-pkg file
# on an Alpine (APK) system.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree

reportResults
