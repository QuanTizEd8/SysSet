#!/bin/bash
# Only the code shim is enabled; devcontainer-info and systemctl are disabled.
set -e

source dev-container-features-test-lib

_SHIM_BIN="/usr/local/share/setup-shim/bin"

# --- code shim installed ---
check "code shim exists"            test -f "${_SHIM_BIN}/code"
check "code shim is executable"     test -x "${_SHIM_BIN}/code"

# --- devcontainer-info NOT installed ---
check "devcontainer-info shim NOT present"  bash -c '! test -f /usr/local/share/setup-shim/bin/devcontainer-info'

# --- systemctl NOT installed ---
check "systemctl shim NOT present"  bash -c '! test -f /usr/local/share/setup-shim/bin/systemctl'

reportResults
