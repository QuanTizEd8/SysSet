#!/bin/bash
# export_path="/tmp/test_bashrc": PATH export is
# written only to the single specified file; no other system files are modified.
set -e

source dev-container-features-test-lib

# --- conda is installed ---
check "conda binary installed"              test -f /opt/conda/bin/conda
check "mamba binary installed"              test -f /opt/conda/bin/mamba

# --- only the specified file is written ---
check "custom target file written"          test -f /tmp/test_bashrc
check "custom target has marked block"      grep -q 'conda PATH (install-miniforge)' /tmp/test_bashrc
check "custom target exports /opt/conda/bin" grep -q '/opt/conda/bin' /tmp/test_bashrc

# --- system files NOT written ---
check "profile.d script NOT written"        bash -c '! test -f /etc/profile.d/conda_bin_path.sh'
check "bash.bashrc NOT modified"            bash -c '! grep -q "conda PATH (install-miniforge)" /etc/bash.bashrc 2>/dev/null'
check "BASH_ENV NOT in /etc/environment"    bash -c '! grep -q "^BASH_ENV=" /etc/environment 2>/dev/null'

reportResults
