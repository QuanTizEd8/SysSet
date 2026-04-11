#!/bin/bash
# bin_dir=/opt/myforge, symlink=false:
# Miniforge is installed to a custom directory.  The default /opt/conda path
# must not be created (symlink disabled), and PATH export blocks must reference
# the custom directory.
set -e

source dev-container-features-test-lib

# --- custom directory structure ---
check "conda installed at /opt/myforge" test -d /opt/myforge
check "conda binary at custom dir" test -f /opt/myforge/bin/conda
check "conda binary is executable" test -x /opt/myforge/bin/conda
check "mamba binary at custom dir" test -f /opt/myforge/bin/mamba
check "mamba binary is executable" test -x /opt/myforge/bin/mamba
check "python installed in custom base env" test -f /opt/myforge/bin/python
check "conda activation script at custom dir" test -f /opt/myforge/etc/profile.d/conda.sh
check "mamba activation script at custom dir" test -f /opt/myforge/etc/profile.d/mamba.sh

# --- default directory must NOT exist (symlink=false) ---
check "default /opt/conda NOT created" bash -c '! test -e /opt/conda'

# --- PATH export references the custom directory ---
echo "=== /etc/profile.d/conda_bin_path.sh ==="
cat /etc/profile.d/conda_bin_path.sh 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/environment ==="
cat /etc/environment 2> /dev/null || echo "(missing)"
echo "=== conda --version ==="
/opt/myforge/bin/conda --version 2>&1 || echo "(failed)"
check "profile.d script written" test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script exports /opt/myforge/bin" grep -q '/opt/myforge/bin' /etc/profile.d/conda_bin_path.sh
check "bash.bashrc exports /opt/myforge/bin" grep -q '/opt/myforge/bin' /etc/bash.bashrc
check "BASH_ENV registered in /etc/environment" grep -q '^BASH_ENV=' /etc/environment
check "bashenv exports /opt/myforge/bin" bash -c 'f="$(grep -m1 "^BASH_ENV=" /etc/environment | sed "s/^BASH_ENV=//; s/^[\"'\'']//; s/[\"'\'']$//")"; grep -q "/opt/myforge/bin" "$f"'

# --- functionality ---
check "conda --version succeeds" /opt/myforge/bin/conda --version
check "mamba --version succeeds" /opt/myforge/bin/mamba --version
check "conda info --base returns /opt/myforge" bash -c '[ "$(/opt/myforge/bin/conda info --base 2>/dev/null)" = "/opt/myforge" ]'

reportResults
