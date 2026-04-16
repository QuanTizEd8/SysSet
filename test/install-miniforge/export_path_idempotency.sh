#!/bin/bash
# export_path idempotency: the base image has PATH blocks for /opt/conda/bin
# already written in all four Case-A files.  The feature runs with
# prefix=/opt/myforge (symlink=false) and must UPDATE each block to reference
# /opt/myforge/bin without appending a duplicate block.
set -e

source dev-container-features-test-lib

# --- conda installed at custom dir ---
check "conda binary at /opt/myforge" test -f /opt/myforge/bin/conda
check "mamba binary at /opt/myforge" test -f /opt/myforge/bin/mamba

echo "=== /etc/profile.d/conda_bin_path.sh ==="
cat /etc/profile.d/conda_bin_path.sh 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"
echo "=== /etc/environment ==="
cat /etc/environment 2> /dev/null || echo "(missing)"
echo "=== /etc/bashenv ==="
cat /etc/bashenv 2> /dev/null || echo "(missing)"

# --- blocks updated to new path ---
check "profile.d block updated to /opt/myforge/bin" grep -q '/opt/myforge/bin' /etc/profile.d/conda_bin_path.sh
check "bash.bashrc block updated to /opt/myforge/bin" grep -q '/opt/myforge/bin' /etc/bash.bashrc
check "zshenv block updated to /opt/myforge/bin" grep -q '/opt/myforge/bin' /etc/zsh/zshenv
check "bashenv block updated to /opt/myforge/bin" bash -c 'f="$(grep -m1 "^BASH_ENV=" /etc/environment | sed "s/^BASH_ENV=//; s/^[\"'\'']//; s/[\"'\'']$//")"; grep -q "/opt/myforge/bin" "$f"'

# --- old path gone from each file ---
check "profile.d block has no old /opt/conda/bin" bash -c '! grep -q "/opt/conda/bin" /etc/profile.d/conda_bin_path.sh'
check "bash.bashrc block has no old /opt/conda/bin" bash -c '! grep -q "/opt/conda/bin" /etc/bash.bashrc'
check "zshenv block has no old /opt/conda/bin" bash -c '! grep -q "/opt/conda/bin" /etc/zsh/zshenv'
check "bashenv block has no old /opt/conda/bin" bash -c 'f="$(grep -m1 "^BASH_ENV=" /etc/environment | sed "s/^BASH_ENV=//; s/^[\"'\'']//; s/[\"'\'']$//")"; ! grep -q "/opt/conda/bin" "$f"'

# --- exactly one block per file (no duplicates) ---
check "profile.d has exactly one begin marker" bash -c '[ "$(grep -c ">>> conda PATH (install-miniforge) >>>" /etc/profile.d/conda_bin_path.sh)" -eq 1 ]'
check "bash.bashrc has exactly one begin marker" bash -c '[ "$(grep -c ">>> conda PATH (install-miniforge) >>>" /etc/bash.bashrc)" -eq 1 ]'
check "zshenv has exactly one begin marker" bash -c '[ "$(grep -c ">>> conda PATH (install-miniforge) >>>" /etc/zsh/zshenv)" -eq 1 ]'
check "bashenv has exactly one begin marker" bash -c 'f="$(grep -m1 "^BASH_ENV=" /etc/environment | sed "s/^BASH_ENV=//; s/^[\"'\'']//; s/[\"'\'']$//")"; [ "$(grep -c ">>> conda PATH (install-miniforge) >>>" "$f")" -eq 1 ]'

reportResults
