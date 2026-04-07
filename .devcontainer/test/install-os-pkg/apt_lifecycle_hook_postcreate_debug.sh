#!/bin/bash
# Same assertions as apt_lifecycle_hook_postcreate but with debug=true,
# so the build log will show the exact LIFECYCLE_HOOK env var value.
set -e

source dev-container-features-test-lib

check "post-create.sh exists" test -f /usr/local/share/install-os-pkg/post-create.sh
check "post-create.sh is executable" test -x /usr/local/share/install-os-pkg/post-create.sh
check "post-create.sh references manifest" grep -q -- '--manifest' /usr/local/share/install-os-pkg/post-create.sh
check "on-create.sh not written" test ! -f /usr/local/share/install-os-pkg/on-create.sh
check "update-content.sh not written" test ! -f /usr/local/share/install-os-pkg/update-content.sh
check "tree installed by postCreate hook" command -v tree

reportResults
