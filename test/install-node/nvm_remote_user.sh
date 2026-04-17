#!/bin/bash
# add_remote_user=true with remoteUser="vscode" (injected as _REMOTE_USER by
# the devcontainer CLI): vscode is added to the nvm group and receives the
# nvm init snippet in ~/.bashrc.
set -e

source dev-container-features-test-lib

_NVM_DIR=/usr/local/share/nvm

# --- nvm and node installed ---
check "node on PATH" command -v node
check "nvm.sh exists" test -f "${_NVM_DIR}/nvm.sh"

# --- group created ---
echo "=== getent group nvm ==="
getent group nvm 2>&1 || echo "(not found)"
echo "=== id vscode ==="
id vscode 2>&1 || echo "(not found)"

check "nvm group exists" bash -c 'getent group nvm >/dev/null 2>&1'

# --- vscode resolved via _REMOTE_USER ---
check "vscode is in nvm group" bash -c 'id -nG vscode | grep -qw nvm'

# --- per-user nvm init written ---
echo "=== /home/vscode/.bashrc (nvm lines) ==="
grep "nvm" /home/vscode/.bashrc 2> /dev/null || echo "(no nvm lines)"

check "vscode .bashrc contains nvm.sh source" bash -c \
  'grep -Fq "nvm.sh" /home/vscode/.bashrc 2>/dev/null'

reportResults
