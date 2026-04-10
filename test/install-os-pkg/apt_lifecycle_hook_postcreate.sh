#!/bin/bash
# Verifies that when lifecycle_hook=postCreate is set, the feature writes a
# post-create.sh hook script instead of installing packages at build time.
set -e

source dev-container-features-test-lib

check "post-create.sh exists" test -f /usr/local/share/install-os-pkg/post-create.sh
check "post-create.sh is executable" test -x /usr/local/share/install-os-pkg/post-create.sh
check "post-create.sh references manifest" grep -q -- '--manifest' /usr/local/share/install-os-pkg/post-create.sh
check "on-create.sh not written" test ! -f /usr/local/share/install-os-pkg/on-create.sh
check "update-content.sh not written" test ! -f /usr/local/share/install-os-pkg/update-content.sh
check "tree installed by postCreate hook" command -v tree

reportResults
