#!/bin/bash
# version=24.7.1 + if_exists=uninstall, with conda 24.7.1 pre-installed:
# The version-match check (installed == resolved) fires before if_exists dispatch,
# so uninstall is never triggered.  Post-install steps (PATH export) still run.
set -e

source dev-container-features-test-lib

# --- conda was not reinstalled or removed ---
check "conda directory still exists"           test -d /opt/conda
check "conda binary still present"             test -f /opt/conda/bin/conda
check "conda binary is executable"             test -x /opt/conda/bin/conda
check "mamba binary still present"             test -f /opt/conda/bin/mamba
check "mamba binary is executable"             test -x /opt/conda/bin/mamba

# --- version is unchanged (uninstall was skipped) ---
echo "=== conda --version ==="; /opt/conda/bin/conda --version 2>&1 || echo "(failed)"
check "conda --version succeeds"               /opt/conda/bin/conda --version
check "conda version is still 24.7.1"          bash -c '[ "$(/opt/conda/bin/conda --version 2>/dev/null | awk "{print \$NF}")" = "24.7.1" ]'
check "conda info --base returns /opt/conda"   bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'

# --- post-install steps ran (PATH export was written) ---
check "profile.d script written"               test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block"      grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh

reportResults
