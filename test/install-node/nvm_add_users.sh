#!/bin/bash
# add_users="testuser" with all other add_*_user=false:
# testuser is added to the nvm group, NVM_DIR user-owned by testuser with
# group-write + setgid bits set, and testuser's ~/.bashrc receives the nvm
# init snippet.
set -e

source dev-container-features-test-lib

_NVM_DIR=/usr/local/share/nvm

# --- nvm and node installed ---
check "node on PATH" command -v node
check "nvm.sh exists" test -f "${_NVM_DIR}/nvm.sh"

# --- group created ---
echo "=== getent group nvm ==="
getent group nvm 2>&1 || echo "(not found)"
echo "=== id testuser ==="
id testuser 2>&1 || echo "(not found)"
echo "=== stat ${_NVM_DIR} ==="
stat -c "user=%U group=%G mode=%A" "${_NVM_DIR}" 2>&1 || echo "(failed)"

check "nvm group exists" bash -c 'getent group nvm >/dev/null 2>&1'

# --- testuser resolved as sole user ---
check "testuser is in nvm group" bash -c 'id -nG testuser | grep -qw nvm'
check "NVM_DIR user-owned by testuser" bash -c '[ "$(stat -c "%U" /usr/local/share/nvm)" = "testuser" ]'

# --- directory permission bits ---
check "NVM_DIR group-owned by nvm" bash -c '[ "$(stat -c "%G" /usr/local/share/nvm)" = "nvm" ]'
check "NVM_DIR is group-writable" bash -c '[ "$(stat -c "%A" /usr/local/share/nvm | cut -c6)" = "w" ]'
check "NVM_DIR has setgid bit" bash -c 'stat -c "%A" /usr/local/share/nvm | grep -qE "^d.....(s|S)"'

# --- per-user nvm init written ---
echo "=== /home/testuser/.bashrc (nvm lines) ==="
grep "nvm" /home/testuser/.bashrc 2> /dev/null || echo "(no nvm lines)"

check "testuser .bashrc contains nvm.sh source" bash -c \
  'grep -Fq "nvm.sh" /home/testuser/.bashrc 2>/dev/null'

reportResults
