#!/bin/bash
# download=true, reinstall=true: conda is pre-installed in the image (see
# Dockerfile).  The feature detects the existing installation, uninstalls it,
# and installs a fresh copy.  Verifies the reinstalled conda is functional.
set -e

source dev-container-features-test-lib

# --- reinstalled conda directory ---
check "conda directory exists after reinstall"   test -d /opt/conda
check "conda binary installed after reinstall"   test -f /opt/conda/bin/conda
check "conda binary is executable"               test -x /opt/conda/bin/conda
check "mamba binary installed after reinstall"   test -f /opt/conda/bin/mamba
check "mamba binary is executable"               test -x /opt/conda/bin/mamba

# --- reinstalled conda is functional ---
check "conda --version succeeds after reinstall"  /opt/conda/bin/conda --version
check "mamba --version succeeds after reinstall"  /opt/conda/bin/mamba --version
check "conda info --base returns /opt/conda"      bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'
check "base environment accessible"               /opt/conda/bin/conda env list

# --- activation scripts exist (fresh install writes them) ---
check "conda activation script exists"            test -f /opt/conda/etc/profile.d/conda.sh

# --- PATH update written (update_path=true by default) ---
check "conda_path.sh written"                     test -f /etc/profile.d/conda_path.sh

reportResults
