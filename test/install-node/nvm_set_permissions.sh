#!/bin/bash
# set_permissions=true (default): nvm group is created, NVM_DIR is group-owned
# by nvm, and has group-write + setgid bits set.
set -e

source dev-container-features-test-lib

_NVM_DIR=/usr/local/share/nvm

# --- nvm and node installed ---
check "node on PATH" command -v node
check "nvm.sh exists" test -f "${_NVM_DIR}/nvm.sh"

# --- group created ---
echo "=== getent group nvm ==="
getent group nvm 2>&1 || echo "(not found)"
echo "=== stat ${_NVM_DIR} ==="
stat -c "user=%U group=%G mode=%A" "${_NVM_DIR}" 2>&1 || echo "(failed)"

check "nvm group exists" bash -c 'getent group nvm >/dev/null 2>&1'

# --- directory ownership and permission bits ---
check "NVM_DIR group-owned by nvm" bash -c '[ "$(stat -c "%G" /usr/local/share/nvm)" = "nvm" ]'
check "NVM_DIR is group-writable" bash -c '[ "$(stat -c "%A" /usr/local/share/nvm | cut -c6)" = "w" ]'
check "NVM_DIR has setgid bit" bash -c 'stat -c "%A" /usr/local/share/nvm | grep -qE "^d.....(s|S)"'

reportResults
