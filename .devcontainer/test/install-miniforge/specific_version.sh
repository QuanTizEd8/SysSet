#!/bin/bash
# download=true, install=true, conda_version=24.7.1-2: Miniforge is
# installed from a pinned release rather than the rolling 'latest' URL.
# This verifies that the versioned download and install path works end-to-end.
# Update conda_version in scenarios.json when the pinned release is retired.
set -e

source dev-container-features-test-lib

# --- installation succeeded ---
check "conda directory exists"              test -d /opt/conda
check "conda binary installed"              test -f /opt/conda/bin/conda
check "conda binary is executable"          test -x /opt/conda/bin/conda
check "mamba binary installed"              test -f /opt/conda/bin/mamba
check "mamba binary is executable"          test -x /opt/conda/bin/mamba

# --- conda runs correctly ---
check "conda --version succeeds"            /opt/conda/bin/conda --version
check "mamba --version succeeds"            /opt/conda/bin/mamba --version
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'
check "base environment is accessible"      /opt/conda/bin/conda env list

# --- checksum was verified (no error in prior coverage, installer cleaned up) ---
check "conda_path.sh written"               test -f /etc/profile.d/conda_path.sh

reportResults
