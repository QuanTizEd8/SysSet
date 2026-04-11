#!/bin/bash
# rc_files=/etc/bash.bashrc, activate_env=myenv:
# 'conda activate myenv' is appended to the rc file instead of the default
# 'conda activate base'.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- rc file written ---
check "/etc/bash.bashrc exists" test -f /etc/bash.bashrc
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"
check "conda.sh sourced in /etc/bash.bashrc" grep -Fq ". '/opt/conda/etc/profile.d/conda.sh'" /etc/bash.bashrc
check "mamba.sh sourced in /etc/bash.bashrc" grep -Fq ". '/opt/conda/etc/profile.d/mamba.sh'" /etc/bash.bashrc

# --- custom active env name ---
check "conda activate myenv in /etc/bash.bashrc" grep -Fq "conda activate myenv" /etc/bash.bashrc

# --- default env name must NOT appear ---
check "conda activate base NOT in /etc/bash.bashrc" bash -c '! grep -Fq "conda activate base" /etc/bash.bashrc'

reportResults
