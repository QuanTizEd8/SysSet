#!/bin/bash
# set_permissions=true, users="testuser1,testuser2":
# both named users are added to the conda group; the conda directory is
# group-owned and has group-write and setgid bits set.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed"                   test -f /opt/conda/bin/conda
check "conda --version succeeds"                 /opt/conda/bin/conda --version

# --- group created ---
check "conda group exists"                       bash -c 'getent group conda >/dev/null 2>&1'

# --- both users added to conda group ---
check "testuser1 is in conda group"              bash -c 'id -nG testuser1 | grep -qw conda'
check "testuser2 is in conda group"              bash -c 'id -nG testuser2 | grep -qw conda'

# --- directory ownership ---
check "/opt/conda group-owned by conda"          bash -c '[ "$(stat -c "%G" /opt/conda)" = "conda" ]'

# --- permission bits ---
check "/opt/conda is group-writable"             bash -c '[ "$(stat -c "%A" /opt/conda | cut -c6)" = "w" ]'
check "/opt/conda has setgid bit"                bash -c 'stat -c "%A" /opt/conda | grep -qE "^d.....(s|S)"'

reportResults
