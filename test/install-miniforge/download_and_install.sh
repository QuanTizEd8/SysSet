#!/bin/bash
# All defaults: full Miniforge installation.
# Verifies conda and mamba are installed under /opt/conda, the base environment
# is functional, activation scripts are in place, and PATH export blocks are
# written to all system-wide shell startup files (export_path defaults to "auto").
set -e

source dev-container-features-test-lib

# --- installation directory structure ---
check "conda directory exists" test -d /opt/conda
check "conda/bin directory exists" test -d /opt/conda/bin
check "conda/envs directory exists" test -d /opt/conda/envs
check "conda/pkgs directory exists" test -d /opt/conda/pkgs

# --- executables ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda
check "mamba binary installed" test -f /opt/conda/bin/mamba
check "mamba binary is executable" test -x /opt/conda/bin/mamba
check "python installed in base env" test -f /opt/conda/bin/python
check "pip installed in base env" test -f /opt/conda/bin/pip

# --- activation scripts ---
check "conda activation script exists" test -f /opt/conda/etc/profile.d/conda.sh
check "mamba activation script exists" test -f /opt/conda/etc/profile.d/mamba.sh

# --- PATH export (export_path=auto by default, Debian Case A: public install + root) ---
echo "=== conda --version ==="
/opt/conda/bin/conda --version 2>&1 || echo "(failed)"
echo "=== /etc/profile.d/conda_bin_path.sh ==="
cat /etc/profile.d/conda_bin_path.sh 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"
echo "=== /etc/environment ==="
cat /etc/environment 2> /dev/null || echo "(missing)"
check "profile.d script written" test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script has marked block" grep -q 'conda PATH (install-miniforge)' /etc/profile.d/conda_bin_path.sh
check "profile.d script exports /opt/conda/bin" grep -q '/opt/conda/bin' /etc/profile.d/conda_bin_path.sh
check "bash.bashrc has marked block" grep -q 'conda PATH (install-miniforge)' /etc/bash.bashrc
check "bash.bashrc exports /opt/conda/bin" grep -q '/opt/conda/bin' /etc/bash.bashrc
check "zshenv has marked block" grep -q 'conda PATH (install-miniforge)' /etc/zsh/zshenv
check "zshenv exports /opt/conda/bin" grep -q '/opt/conda/bin' /etc/zsh/zshenv
check "BASH_ENV registered in /etc/environment" grep -q '^BASH_ENV=' /etc/environment
check "bashenv file has marked block" bash -c 'f="$(grep -m1 "^BASH_ENV=" /etc/environment | sed "s/^BASH_ENV=//; s/^[\"'\'']//; s/[\"'\'']$//")"; grep -q "conda PATH (install-miniforge)" "$f"'
check "bashenv exports /opt/conda/bin" bash -c 'f="$(grep -m1 "^BASH_ENV=" /etc/environment | sed "s/^BASH_ENV=//; s/^[\"'\'']//; s/[\"'\'']$//")"; grep -q "/opt/conda/bin" "$f"'
check "login PATH includes /opt/conda/bin" bash -lc 'echo "$PATH"' | grep -q '/opt/conda/bin'

# --- conda functionality ---
check "conda --version succeeds" /opt/conda/bin/conda --version
check "mamba --version succeeds" /opt/conda/bin/mamba --version
check "conda info exits zero" /opt/conda/bin/conda info
check "conda env list shows base" /opt/conda/bin/conda env list
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'
check "conda list for base env succeeds" /opt/conda/bin/conda list -n base

# --- no stray installer artifacts (keep_installer=false by default) ---
check "installer dir cleaned up" bash -c '! test -f /tmp/miniforge-installer/*.sh 2>/dev/null'

reportResults
