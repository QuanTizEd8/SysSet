#!/bin/bash
# Default options (bin_dir=/opt/conda, export_path=auto):
# Verifies that all system-wide PATH export blocks are written on Debian/Ubuntu
# (Case A: public install + root).
set -e

source dev-container-features-test-lib

# --- profile.d login-shell script ---
echo "=== /etc/profile.d/conda_bin_path.sh ==="
cat /etc/profile.d/conda_bin_path.sh 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"
echo "=== /etc/environment ==="
cat /etc/environment 2> /dev/null || echo "(missing)"
echo "=== login PATH ==="
bash -lc 'echo "$PATH"' 2>&1 || echo "(failed)"
check "profile.d script written" test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block" grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh
check "profile.d script exports /opt/conda/bin" grep -q '/opt/conda/bin' /etc/profile.d/conda_bin_path.sh

# --- global bashrc (non-login interactive bash) ---
check "bash.bashrc has marked block" grep -q 'conda PATH (install-miniforge)' /etc/bash.bashrc
check "bash.bashrc exports /opt/conda/bin" grep -q '/opt/conda/bin' /etc/bash.bashrc

# --- global zshenv (all Zsh) ---
check "zshenv has marked block" grep -q 'conda PATH (install-miniforge)' /etc/zsh/zshenv
check "zshenv exports /opt/conda/bin" grep -q '/opt/conda/bin' /etc/zsh/zshenv

# --- BASH_ENV / bashenv (non-login non-interactive bash) ---
check "BASH_ENV registered in /etc/environment" grep -q '^BASH_ENV=' /etc/environment
check "bashenv file has marked block" bash -c 'f="$(grep -m1 "^BASH_ENV=" /etc/environment | sed "s/^BASH_ENV=//; s/^[\"'\'']//; s/[\"'\'']$//")"; grep -q "conda PATH (install-miniforge)" "$f"'
check "bashenv exports /opt/conda/bin" bash -c 'f="$(grep -m1 "^BASH_ENV=" /etc/environment | sed "s/^BASH_ENV=//; s/^[\"'\'']//; s/[\"'\'']$//")"; grep -q "/opt/conda/bin" "$f"'

# --- no symlink needed (default path) ---
check "/opt/conda is a real directory not a symlink" bash -c '[ -d /opt/conda ] && [ ! -L /opt/conda ]'

# --- runtime PATH check ---
check "login PATH includes /opt/conda/bin" bash -lc 'echo "$PATH"' | grep -q '/opt/conda/bin'

reportResults
