#!/bin/bash
# download=true, install=true: full Miniforge installation with all defaults.
# Verifies conda and mamba are installed under /opt/conda, the base environment
# is functional, activation scripts are in place, and /etc/profile.d/conda_path.sh
# is written because update_path defaults to true.
set -e

source dev-container-features-test-lib

# --- installation directory structure ---
check "conda directory exists"                   test -d /opt/conda
check "conda/bin directory exists"               test -d /opt/conda/bin
check "conda/envs directory exists"              test -d /opt/conda/envs
check "conda/pkgs directory exists"              test -d /opt/conda/pkgs

# --- executables ---
check "conda binary installed"                   test -f /opt/conda/bin/conda
check "conda binary is executable"               test -x /opt/conda/bin/conda
check "mamba binary installed"                   test -f /opt/conda/bin/mamba
check "mamba binary is executable"               test -x /opt/conda/bin/mamba
check "python installed in base env"             test -f /opt/conda/bin/python
check "pip installed in base env"                test -f /opt/conda/bin/pip

# --- activation scripts ---
check "conda activation script exists"           test -f /opt/conda/etc/profile.d/conda.sh
check "mamba activation script exists"           test -f /opt/conda/etc/profile.d/mamba.sh

# --- PATH update (update_path=true by default) ---
check "conda_path.sh written"                    test -f /etc/profile.d/conda_path.sh
check "conda_path.sh exports /opt/conda/bin"     grep -q '/opt/conda/bin' /etc/profile.d/conda_path.sh
check "conda_path.sh uses export"                grep -q 'export PATH' /etc/profile.d/conda_path.sh

# --- conda functionality ---
check "conda --version succeeds"                 /opt/conda/bin/conda --version
check "mamba --version succeeds"                 /opt/conda/bin/mamba --version
check "conda info exits zero"                    /opt/conda/bin/conda info
check "conda env list shows base"                /opt/conda/bin/conda env list
check "conda info --base returns /opt/conda"     bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'
check "conda list for base env succeeds"         /opt/conda/bin/conda list -n base

# --- no stray installer artifacts (no_clean=false by default) ---
check "installer dir cleaned up"                 bash -c '! test -f /tmp/miniforge-installer/*.sh 2>/dev/null'

reportResults
