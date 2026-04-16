#!/bin/bash
# preserve_config=false + if_exists=reinstall with pre-existing conda 24.7.1,
# a /root/.condarc, and a conda initialize block in /root/.bashrc:
# the feature runs conda init --reverse and deletes .condarc/.conda,
# so neither survives after uninstall + reinstall.
set -e

source dev-container-features-test-lib

# --- conda reinstalled ---
check "conda directory exists" test -d /opt/conda
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- .condarc was removed ---
echo "=== /root/.condarc ==="
cat /root/.condarc 2> /dev/null || echo "(not present)"
echo "=== /root/.bashrc (conda initialize block) ==="
grep -A3 'conda initialize' /root/.bashrc 2> /dev/null || echo "(no conda initialize block)"
check ".condarc removed" bash -c '[ ! -f /root/.condarc ]'

# --- conda initialize block removed from .bashrc ---
check ".bashrc has no conda initialize block" bash -c '! grep -q "conda initialize" /root/.bashrc'

# --- PATH export written ---
check "profile.d script written" test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block" grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh

reportResults
