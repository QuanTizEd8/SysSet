#!/bin/bash
# export_path="": Miniforge is installed but PATH export blocks are NOT written
# to any shell startup files.  conda is still reachable via containerEnv.PATH
# (the container-level PATH set by the devcontainer spec), but shell startup
# files must not be written.
set -e

source dev-container-features-test-lib

# --- conda is still installed ---
check "conda binary installed"           test -f /opt/conda/bin/conda
check "conda binary is executable"       test -x /opt/conda/bin/conda
check "mamba binary installed"           test -f /opt/conda/bin/mamba
check "conda --version succeeds"         /opt/conda/bin/conda --version

# --- PATH export files must NOT exist or be written ---
echo "=== /etc/profile.d/conda_bin_path.sh ==="; cat /etc/profile.d/conda_bin_path.sh 2>/dev/null || echo "(not present)"
echo "=== /etc/bash.bashrc (conda PATH block) ==="; grep 'conda PATH' /etc/bash.bashrc 2>/dev/null || echo "(no block)"
echo "=== /etc/environment (BASH_ENV) ==="; grep 'BASH_ENV' /etc/environment 2>/dev/null || echo "(no BASH_ENV)"
check "profile.d script NOT written"     bash -c '! test -f /etc/profile.d/conda_bin_path.sh'
check "bash.bashrc NOT modified"         bash -c '! grep -q "conda PATH (install-miniforge)" /etc/bash.bashrc 2>/dev/null'
check "BASH_ENV NOT added to /etc/environment" bash -c '! grep -q "^BASH_ENV=" /etc/environment 2>/dev/null'

reportResults
