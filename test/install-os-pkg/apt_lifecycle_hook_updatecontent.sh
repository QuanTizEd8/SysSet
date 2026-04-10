#!/bin/bash
# Verifies that when lifecycle_hook=updateContent is set, the feature writes an
# update-content.sh hook script and defers package installation to that hook.
set -e

source dev-container-features-test-lib

check "update-content.sh exists" test -f /usr/local/share/install-os-pkg/update-content.sh
check "update-content.sh is executable" test -x /usr/local/share/install-os-pkg/update-content.sh
check "update-content.sh references manifest" grep -q -- '--manifest' /usr/local/share/install-os-pkg/update-content.sh
check "on-create.sh not written" test ! -f /usr/local/share/install-os-pkg/on-create.sh
check "post-create.sh not written" test ! -f /usr/local/share/install-os-pkg/post-create.sh
check "tree installed by updateContent hook" command -v tree

reportResults
