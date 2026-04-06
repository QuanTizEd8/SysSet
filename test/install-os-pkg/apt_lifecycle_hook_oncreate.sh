#!/bin/bash
# Verifies that when lifecycle_hook=onCreate is set, the feature writes an
# on-create.sh hook script and defers package installation to that hook.
set -e

source dev-container-features-test-lib

check "on-create.sh exists" test -f /usr/local/share/install-os-pkg/on-create.sh
check "on-create.sh is executable" test -x /usr/local/share/install-os-pkg/on-create.sh
check "on-create.sh references manifest" grep -q -- '--manifest' /usr/local/share/install-os-pkg/on-create.sh
check "post-create.sh not written" test ! -f /usr/local/share/install-os-pkg/post-create.sh
check "update-content.sh not written" test ! -f /usr/local/share/install-os-pkg/update-content.sh
check "tree installed by onCreate hook" command -v tree

reportResults
