#!/bin/bash
# Verifies that skip_installed=true skips packages whose binary is already
# present in PATH, even if they were not installed via the package manager.
#
# The Dockerfile places a fake 'mytool' binary at /usr/local/bin/mytool.
# 'mytool' is not a real apt package: if the feature tried to install it the
# build would fail.  The fact that the build succeeds proves the skip worked.
#
# 'tree' is a real package absent from the base image and must still be
# installed, proving that skip_installed only skips what is already in PATH.
set -e

source dev-container-features-test-lib

check "build succeeded (mytool was skipped, not passed to apt)" true
check "mytool is the original fake binary (not overwritten)" bash -c "mytool | grep -q mytool-ok"
check "tree was installed (not in PATH before the feature ran)" command -v tree

reportResults
