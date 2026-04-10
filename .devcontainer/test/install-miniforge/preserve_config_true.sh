#!/bin/bash
# preserve_config=true + if_exists=uninstall with pre-existing conda 24.7.1,
# a /root/.condarc, and a conda initialize block in /root/.bashrc:
# the feature skips conda init --reverse and skips .condarc/.conda deletion,
# so both survive after uninstall + reinstall.
set -e

source dev-container-features-test-lib

# --- conda reinstalled ---
check "conda directory exists"              test -d /opt/conda
check "conda binary installed"              test -f /opt/conda/bin/conda
check "conda binary is executable"          test -x /opt/conda/bin/conda
check "conda --version succeeds"            /opt/conda/bin/conda --version

# --- .condarc was preserved ---
check ".condarc still exists"               test -f /root/.condarc
check ".condarc has expected content"       grep -q 'auto_activate_base' /root/.condarc

# --- conda initialize block still in .bashrc ---
check ".bashrc has conda initialize block"  grep -q 'conda initialize' /root/.bashrc

# --- PATH export written ---
check "profile.d script written"            test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block"   grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh

reportResults
