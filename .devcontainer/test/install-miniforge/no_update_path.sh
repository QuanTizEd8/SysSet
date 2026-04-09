#!/bin/bash
# download=true, install=true, update_path=false: Miniforge is installed but
# /etc/profile.d/conda_path.sh is NOT written, so conda is not on the default
# PATH for subsequent shell sessions.
set -e

source dev-container-features-test-lib

# --- conda is still installed ---
check "conda binary installed"           test -f /opt/conda/bin/conda
check "conda binary is executable"       test -x /opt/conda/bin/conda
check "mamba binary installed"           test -f /opt/conda/bin/mamba
check "conda --version succeeds"         /opt/conda/bin/conda --version

# --- PATH update file must NOT exist ---
check "conda_path.sh NOT written"        bash -c '! test -f /etc/profile.d/conda_path.sh'

# --- conda must NOT be on the login PATH ---
check "conda not on default PATH"        bash -c '! command -v conda 2>/dev/null'

reportResults
