#!/bin/bash
# Verifies that install.sh does not abort when add_user_config names a user
# that does not exist. The script should skip that user with a warning and
# still successfully install the shared infrastructure.
set -e

source dev-container-features-test-lib

# --- install succeeded: shared infrastructure is present ---
check "podman is installed"       command -v podman
check "entrypoint exists"         test -f /usr/local/share/install-podman/entrypoint
check "containers.conf exists"    test -f /etc/containers/containers.conf

# --- nonexistent user was skipped, not written ---
check "ghost NOT in /etc/subuid"               bash -c '! grep -q "^ghost:" /etc/subuid 2>/dev/null'
check "ghost config dir NOT written"           bash -c '! test -d /home/ghost'

reportResults
