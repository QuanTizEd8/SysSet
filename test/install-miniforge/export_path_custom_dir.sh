#!/bin/bash
# bin_dir=/opt/myforge, symlink=false:
# All PATH export blocks must reference the custom directory; /opt/conda must
# not exist in any form (symlink disabled).
set -e

source dev-container-features-test-lib

# --- conda at custom dir ---
check "conda installed at /opt/myforge" test -d /opt/myforge
check "conda binary at custom dir" test -f /opt/myforge/bin/conda
check "mamba binary at custom dir" test -f /opt/myforge/bin/mamba

# --- /opt/conda absent (symlink=false) ---
echo "=== ls /opt ==="
ls /opt 2> /dev/null || echo "(failed)"
check "/opt/conda does not exist" bash -c '! test -e /opt/conda'

# --- all PATH export files reference /opt/myforge/bin ---
echo "=== /etc/profile.d/conda_bin_path.sh ==="
cat /etc/profile.d/conda_bin_path.sh 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"
echo "=== /etc/environment ==="
cat /etc/environment 2> /dev/null || echo "(missing)"
check "profile.d script written" test -f /etc/profile.d/conda_bin_path.sh
check "profile.d script exports /opt/myforge/bin" grep -q '/opt/myforge/bin' /etc/profile.d/conda_bin_path.sh
check "bash.bashrc exports /opt/myforge/bin" grep -q '/opt/myforge/bin' /etc/bash.bashrc
check "zshenv exports /opt/myforge/bin" grep -q '/opt/myforge/bin' /etc/zsh/zshenv
check "BASH_ENV registered in /etc/environment" grep -q '^BASH_ENV=' /etc/environment
check "bashenv exports /opt/myforge/bin" bash -c 'f="$(grep -m1 "^BASH_ENV=" /etc/environment | sed "s/^BASH_ENV=//; s/^[\"'\'']//; s/[\"'\'']$//")"; grep -q "/opt/myforge/bin" "$f"'

# --- login PATH uses custom dir ---
check "login PATH includes /opt/myforge/bin" bash -lc 'echo "$PATH"' | grep -q '/opt/myforge/bin'

reportResults
