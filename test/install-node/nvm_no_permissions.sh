#!/bin/bash
# set_permissions=false: node is installed but the nvm group is NOT created.
set -e

source dev-container-features-test-lib

_NVM_DIR=/usr/local/share/nvm

# --- nvm and node installed ---
check "node on PATH" command -v node
check "nvm.sh exists" test -f "${_NVM_DIR}/nvm.sh"

# --- no nvm group created ---
echo "=== getent group nvm (should be absent) ==="
getent group nvm 2>&1 || echo "(not found — expected)"

check "nvm group does not exist" bash -c '! getent group nvm >/dev/null 2>&1'

reportResults
