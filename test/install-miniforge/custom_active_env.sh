#!/bin/bash
# rc_files=/etc/bash.bashrc, activate_env=myenv:
# 'conda activate myenv' is written inside our idempotency block after the
# conda init block; 'conda activate base' must not appear.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- rc file written ---
check "/etc/bash.bashrc exists" test -f /etc/bash.bashrc
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"

# --- our idempotency block is present ---
check "miniforge begin marker in /etc/bash.bashrc" grep -Fq "# >>> conda init (install-miniforge) >>>" /etc/bash.bashrc
check "conda initialize begin marker in /etc/bash.bashrc" grep -Fq "# >>> conda initialize >>>" /etc/bash.bashrc

# --- custom activate line is inside our block ---
check "conda activate myenv in /etc/bash.bashrc" grep -Fq "conda activate myenv" /etc/bash.bashrc

# --- default env name must NOT appear ---
check "conda activate base NOT in /etc/bash.bashrc" bash -c '! grep -Fq "conda activate base" /etc/bash.bashrc'

reportResults
