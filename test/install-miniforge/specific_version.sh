#!/bin/bash
# version=24.7.1: Miniforge is installed from a pinned release resolved
# via the GitHub API (conda 24.7.1 -> tag 24.7.1-2).
# Verifies the versioned download and install path works end-to-end and that
# the installed conda version matches the requested version string exactly.
# Update version in scenarios.json when the pinned release is retired.
set -e

source dev-container-features-test-lib

# --- installation succeeded ---
check "conda directory exists" test -d /opt/conda
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda
check "mamba binary installed" test -f /opt/conda/bin/mamba
check "mamba binary is executable" test -x /opt/conda/bin/mamba

# --- exact conda version installed ---
echo "=== conda --version ==="
/opt/conda/bin/conda --version 2>&1 || echo "(failed)"
check "conda --version succeeds" /opt/conda/bin/conda --version
check "conda version is 24.7.1" bash -c '[ "$(/opt/conda/bin/conda --version 2>/dev/null | awk "{print \$NF}")" = "24.7.1" ]'
check "mamba --version succeeds" /opt/conda/bin/mamba --version
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'
check "base environment is accessible" /opt/conda/bin/conda env list

# --- PATH export written ---
check "profile.d script written" test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block" grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh

reportResults
