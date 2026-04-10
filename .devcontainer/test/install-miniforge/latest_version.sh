#!/bin/bash
# conda_version=latest (default): the script calls the GitHub API to resolve
# the current latest Miniforge release tag and installs from that tag.
# Verifies that installation succeeds and the resolved version is non-empty.
set -e

source dev-container-features-test-lib

# --- installation succeeded ---
check "conda directory exists"              test -d /opt/conda
check "conda binary installed"              test -f /opt/conda/bin/conda
check "conda binary is executable"          test -x /opt/conda/bin/conda
check "mamba binary installed"              test -f /opt/conda/bin/mamba
check "mamba binary is executable"          test -x /opt/conda/bin/mamba

# --- conda runs and reports a non-empty version ---
check "conda --version succeeds"            /opt/conda/bin/conda --version
check "conda version is non-empty"          bash -c '[ -n "$(/opt/conda/bin/conda --version 2>/dev/null)" ]'
check "mamba --version succeeds"            /opt/conda/bin/mamba --version
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'
check "base environment is accessible"      /opt/conda/bin/conda env list

# --- PATH export written ---
check "profile.d script written"            test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block"   grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh

reportResults
