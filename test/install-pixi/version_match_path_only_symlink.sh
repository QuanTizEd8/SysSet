#!/bin/bash
# version=0.41.0 + bin_dir=/opt/pixi-bin + symlink=true, with pixi 0.41.0 only
# on PATH (see Dockerfile).
# The version-match shortcut must not skip installing the requested bin_dir
# artifact or leave /usr/local/bin/pixi pointing at a missing target.
set -e

source dev-container-features-test-lib

# --- requested install target is materialised ---
check "pixi binary installed at /opt/pixi-bin/pixi" test -f /opt/pixi-bin/pixi
check "pixi binary is executable at /opt/pixi-bin/pixi" test -x /opt/pixi-bin/pixi

# --- symlink target is real and callable ---
echo "=== /usr/local/bin/pixi ==="
ls -l /usr/local/bin/pixi 2> /dev/null || echo "(missing)"
check "symlink exists at /usr/local/bin/pixi" test -L /usr/local/bin/pixi
check "symlink target exists" test -e /usr/local/bin/pixi
check "symlink points to /opt/pixi-bin/pixi" bash -c '[ "$(readlink /usr/local/bin/pixi)" = "/opt/pixi-bin/pixi" ]'
check "symlinked pixi is callable" /usr/local/bin/pixi --version

reportResults
