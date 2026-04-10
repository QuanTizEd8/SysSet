#!/bin/bash
# if_exists=update with pre-existing conda 24.7.1 and a named environment
# "myenv": the feature resolves latest, sees a version mismatch, and runs
# conda install --name base to update conda in-place without touching named envs.
# Asserts that conda is updated beyond 24.7.1 and myenv still exists.
set -e

source dev-container-features-test-lib

# --- conda is still installed ---
check "conda directory exists"              test -d /opt/conda
check "conda binary installed"              test -f /opt/conda/bin/conda
check "conda binary is executable"          test -x /opt/conda/bin/conda

# --- conda version was updated ---
check "conda --version succeeds"            /opt/conda/bin/conda --version
check "conda version is not 24.7.1"         bash -c '[ "$(/opt/conda/bin/conda --version 2>/dev/null | awk "{print \$NF}")" != "24.7.1" ]'

# --- named environment was left intact ---
check "myenv directory exists"              test -d /opt/conda/envs/myenv
check "conda env list includes myenv"       bash -c '/opt/conda/bin/conda env list | grep -q myenv'

# --- PATH export written ---
check "profile.d script written"            test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block"   grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh

reportResults
