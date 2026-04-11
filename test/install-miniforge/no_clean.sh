#!/bin/bash
# keep_installer=true: the Miniforge installer script
# is NOT removed after installation.  Verifies that the installer directory
# and the .sh file survive the cleanup trap.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- installer artifacts preserved ---
echo "=== ls /tmp/miniforge-installer/ ==="
ls -la /tmp/miniforge-installer/ 2> /dev/null || echo "(missing or empty)"
check "installer directory preserved" test -d /tmp/miniforge-installer
check "installer .sh file preserved" bash -c 'ls /tmp/miniforge-installer/*.sh 2>/dev/null | grep -q .'

reportResults
