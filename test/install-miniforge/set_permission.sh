#!/bin/bash
# set_permissions=true: after installation the
# 'conda' group is created, the running user is added to it, and the conda
# directory is group-owned with group-write and setgid bits.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- group created ---
echo "=== getent group conda ==="
getent group conda 2>&1 || echo "(not found)"
echo "=== id (current user) ==="
id 2>&1 || echo "(failed)"
echo "=== stat /opt/conda ==="
stat -c "user=%U group=%G mode=%A" /opt/conda 2>&1 || echo "(failed)"
check "conda group exists" bash -c 'getent group conda >/dev/null 2>&1'

# --- running user added to conda group ---
check "current user is in conda group" bash -c 'id -nG | grep -qw conda'

# --- directory ownership ---
check "/opt/conda group-owned by conda" bash -c '[ "$(stat -c "%G" /opt/conda)" = "conda" ]'

# --- permission bits ---
check "/opt/conda is group-writable" bash -c '[ "$(stat -c "%A" /opt/conda | cut -c6)" = "w" ]'
check "/opt/conda has setgid bit" bash -c 'stat -c "%A" /opt/conda | grep -qE "^d.....(s|S)"'

reportResults
