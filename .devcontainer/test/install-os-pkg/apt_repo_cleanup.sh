#!/bin/bash
# Verifies that when keep_repos is not set (default false), the APT sources
# drop-in file written during installation is removed after the run.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree
check "syspkg-installer.list removed" test ! -f /etc/apt/sources.list.d/syspkg-installer.list

reportResults
