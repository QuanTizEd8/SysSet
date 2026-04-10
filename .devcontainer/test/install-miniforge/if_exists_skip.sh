#!/bin/bash
# if_exists=skip: conda is pre-installed in the image (see Dockerfile).
# The feature detects the existing installation and skips reinstalling,
# continuing to post-install steps (PATH export, symlink, etc.).
set -e

source dev-container-features-test-lib

# --- original conda installation is intact ---
check "conda directory exists"              test -d /opt/conda
check "conda binary present"               test -f /opt/conda/bin/conda
check "conda binary is executable"         test -x /opt/conda/bin/conda
check "mamba binary present"               test -f /opt/conda/bin/mamba
check "mamba binary is executable"         test -x /opt/conda/bin/mamba

# --- conda is still functional ---
check "conda --version succeeds"           /opt/conda/bin/conda --version
check "mamba --version succeeds"           /opt/conda/bin/mamba --version
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'

# --- post-install steps ran (PATH export written by feature) ---
check "profile.d script written"           test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block"  grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh

reportResults
