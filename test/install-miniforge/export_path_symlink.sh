#!/bin/bash
# prefix=/opt/myforge, symlink=true:
# A symlink /opt/conda -> /opt/myforge must be created so that containerEnv
# PATH coverage works via /opt/conda/bin even with a custom prefix.
set -e

source dev-container-features-test-lib

# --- conda at custom dir ---
check "conda installed at /opt/myforge" test -d /opt/myforge
check "conda binary at custom dir" test -f /opt/myforge/bin/conda
check "mamba binary at custom dir" test -f /opt/myforge/bin/mamba

# --- symlink created ---
echo "=== ls -la /opt ==="
ls -la /opt 2> /dev/null || echo "(failed)"
echo "=== /etc/profile.d/conda_bin_path.sh ==="
cat /etc/profile.d/conda_bin_path.sh 2> /dev/null || echo "(missing)"
check "/opt/conda is a symlink" test -L /opt/conda
check "/opt/conda symlink points to /opt/myforge" bash -c '[ "$(readlink /opt/conda)" = "/opt/myforge" ]'
check "/opt/conda/bin/conda reachable via symlink" test -f /opt/conda/bin/conda
check "conda --version via symlink" /opt/conda/bin/conda --version

# --- PATH export files reference /opt/myforge/bin ---
check "profile.d script written" test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script exports /opt/myforge/bin" grep -q '/opt/myforge/bin' /etc/profile.d/conda_bin_path.sh

reportResults
