#!/bin/bash
# download=true, install=true, export_path="": Miniforge is installed but PATH
# export blocks are NOT written to any shell startup files, so conda is not on
# the default PATH for subsequent shell sessions.
set -e

source dev-container-features-test-lib

# --- conda is still installed ---
check "conda binary installed"           test -f /opt/conda/bin/conda
check "conda binary is executable"       test -x /opt/conda/bin/conda
check "mamba binary installed"           test -f /opt/conda/bin/mamba
check "conda --version succeeds"         /opt/conda/bin/conda --version

# --- PATH export files must NOT exist or be written ---
check "profile.d script NOT written"     bash -c '! test -f /etc/profile.d/conda_bin_path.sh'
check "bash.bashrc NOT modified"         bash -c '! grep -q "conda PATH (install-miniforge)" /etc/bash.bashrc 2>/dev/null'
check "BASH_ENV NOT added to /etc/environment" bash -c '! grep -q "^BASH_ENV=" /etc/environment 2>/dev/null'

# --- conda must NOT be on the login PATH ---
check "conda not on default PATH"        bash -c '! command -v conda 2>/dev/null'

reportResults
