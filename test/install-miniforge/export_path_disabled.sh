#!/bin/bash
# export_path="": PATH export is disabled so none of the system shell startup
# files are written or modified.  conda is still reachable via containerEnv.PATH
# (the container-level PATH), but the shell startup files must not be touched.
set -e

source dev-container-features-test-lib

# --- conda is still installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda
check "mamba binary installed" test -f /opt/conda/bin/mamba
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- no PATH export files written ---
echo "=== /etc/profile.d/conda_bin_path.sh ==="
cat /etc/profile.d/conda_bin_path.sh 2> /dev/null || echo "(not present)"
echo "=== /etc/bash.bashrc (conda PATH block) ==="
grep 'conda PATH' /etc/bash.bashrc 2> /dev/null || echo "(no block)"
echo "=== /etc/zsh/zshenv (conda PATH block) ==="
grep 'conda PATH' /etc/zsh/zshenv 2> /dev/null || echo "(no block)"
echo "=== /etc/environment (BASH_ENV) ==="
grep 'BASH_ENV' /etc/environment 2> /dev/null || echo "(no BASH_ENV)"
check "profile.d script NOT written" bash -c '! test -f /etc/profile.d/conda_bin_path.sh'
check "bash.bashrc NOT modified" bash -c '! grep -q "conda PATH (install-miniforge)" /etc/bash.bashrc 2>/dev/null'
check "zshenv NOT written" bash -c '! test -f /etc/zsh/zshenv || ! grep -q "conda PATH (install-miniforge)" /etc/zsh/zshenv'
check "BASH_ENV NOT in /etc/environment" bash -c '! grep -q "^BASH_ENV=" /etc/environment 2>/dev/null'

reportResults
