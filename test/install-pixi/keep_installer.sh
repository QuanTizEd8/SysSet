#!/bin/bash
# keep_installer=true: the downloaded .tar.gz archive and .tar.gz.sha256 sidecar
# must remain in installer_dir after installation completes.
set -e

source dev-container-features-test-lib

# --- pixi installed and functional ---
check "pixi binary installed" test -f /usr/local/bin/pixi
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- archive preserved ---
echo "=== /tmp/pixi-installer/ contents ==="
ls -la /tmp/pixi-installer/ 2> /dev/null || echo "(directory missing)"
check "installer_dir exists" test -d /tmp/pixi-installer
check "pixi archive preserved" bash -c 'ls /tmp/pixi-installer/pixi-*.tar.gz 2>/dev/null | grep -q .'
check "pixi sidecar preserved" bash -c 'ls /tmp/pixi-installer/pixi-*.tar.gz.sha256 2>/dev/null | grep -q .'

reportResults
