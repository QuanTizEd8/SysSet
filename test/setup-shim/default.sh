#!/bin/bash
# Default options: all three shims enabled.
# Verifies each shim is installed, executable, and on PATH at the expected
# location.  Also checks that the shim directory is first in PATH.
set -e

source dev-container-features-test-lib

_SHIM_BIN="/usr/local/share/setup-shim/bin"

# --- shim directory exists and is in PATH ---
check "shim bin directory exists"    test -d "${_SHIM_BIN}"
check "shim bin is in PATH"         bash -c 'echo "$PATH" | tr ":" "\n" | grep -qxF "/usr/local/share/setup-shim/bin"'
check "shim bin is first in PATH"   bash -c '[ "$(echo "$PATH" | cut -d: -f1)" = "/usr/local/share/setup-shim/bin" ]'

# --- code shim ---
check "code shim exists"            test -f "${_SHIM_BIN}/code"
check "code shim is executable"     test -x "${_SHIM_BIN}/code"
check "which code resolves to shim" bash -c '[ "$(which code)" = "/usr/local/share/setup-shim/bin/code" ]'

# --- devcontainer-info shim ---
check "devcontainer-info shim exists"         test -f "${_SHIM_BIN}/devcontainer-info"
check "devcontainer-info shim is executable"  test -x "${_SHIM_BIN}/devcontainer-info"
check "which devcontainer-info resolves to shim" bash -c '[ "$(which devcontainer-info)" = "/usr/local/share/setup-shim/bin/devcontainer-info" ]'

# --- systemctl shim ---
check "systemctl shim exists"            test -f "${_SHIM_BIN}/systemctl"
check "systemctl shim is executable"     test -x "${_SHIM_BIN}/systemctl"

reportResults
