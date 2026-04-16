#!/bin/bash
# preserve_envs=false + if_exists=reinstall with pre-existing conda 24.7.1 and
# a named environment "myenv": the feature resolves latest, sees a version
# mismatch, skips env export, uninstalls, then reinstalls fresh conda without
# recreating any environments.
# Asserts that myenv does NOT exist after the cycle.
set -e

source dev-container-features-test-lib

# --- conda reinstalled ---
check "conda directory exists" test -d /opt/conda
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda

# --- named environment was NOT preserved ---
echo "=== conda env list ==="
/opt/conda/bin/conda env list 2>&1 || echo "(failed)"
check "myenv directory removed" bash -c '[ ! -d /opt/conda/envs/myenv ]'

# --- conda is functional ---
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- PATH export written ---
check "profile.d script written" test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block" grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh

reportResults
