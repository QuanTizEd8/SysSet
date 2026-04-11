#!/bin/bash
# preserve_envs=true + if_exists=uninstall with pre-existing conda 24.7.1 and
# a named environment "myenv": the feature resolves latest, sees a version
# mismatch, exports myenv before uninstalling, reinstalls fresh conda, then
# recreates myenv from the exported YAML.
# Asserts that myenv exists after the full cycle.
set -e

source dev-container-features-test-lib

# --- conda reinstalled ---
check "conda directory exists" test -d /opt/conda
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda

# --- named environment was preserved ---
echo "=== conda env list ==="
/opt/conda/bin/conda env list 2>&1 || echo "(failed)"
check "myenv directory exists" test -d /opt/conda/envs/myenv

# --- conda is functional ---
check "conda --version succeeds" /opt/conda/bin/conda --version
check "conda env list includes myenv" bash -c '/opt/conda/bin/conda env list | grep -q myenv'

# --- PATH export written ---
check "profile.d script written" test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block" grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh

reportResults
