#!/bin/bash
# shell_activations=bash: conda init block is written to the system-wide
# bash rc file exactly once using our own idempotency markers.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- activation rc file was written ---
check "/etc/bash.bashrc exists" test -f /etc/bash.bashrc
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"

# --- our idempotency block markers are present ---
check "miniforge begin marker in /etc/bash.bashrc" grep -Fq "# >>> conda init (install-miniforge) >>>" /etc/bash.bashrc
check "miniforge end marker in /etc/bash.bashrc" grep -Fq "# <<< conda init (install-miniforge) <<<" /etc/bash.bashrc

# --- conda's own markers are present inside the block ---
check "conda initialize begin marker in /etc/bash.bashrc" grep -Fq "# >>> conda initialize >>>" /etc/bash.bashrc
check "conda initialize end marker in /etc/bash.bashrc" grep -Fq "# <<< conda initialize <<<" /etc/bash.bashrc

# --- activate_env=base: no explicit 'conda activate base' line (handled by .condarc) ---
check "conda activate base NOT in /etc/bash.bashrc" bash -c '! grep -Fq "conda activate base" /etc/bash.bashrc'

# --- idempotency: our block marker appears exactly once ---
check "miniforge begin marker not duplicated" bash -c '[ "$(grep -Fc "# >>> conda init (install-miniforge) >>>" /etc/bash.bashrc)" -eq 1 ]'

reportResults
