#!/bin/bash
# user_shell=/bin/sh: login shell is set to /bin/sh instead of the default /bin/bash.
set -e

source dev-container-features-test-lib

# --- user account ---
check "vscode user exists"    bash -c 'id vscode > /dev/null 2>&1'

# --- shell ---
check "login shell is /bin/sh"    bash -c '[ "$(awk -F: '\''$1=="vscode"{print $7}'\'' /etc/passwd)" = "/bin/sh" ]'
check "login shell is NOT /bin/bash"  bash -c '[ "$(awk -F: '\''$1=="vscode"{print $7}'\'' /etc/passwd)" != "/bin/bash" ]'

reportResults
