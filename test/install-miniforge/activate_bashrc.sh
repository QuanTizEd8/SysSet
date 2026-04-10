#!/bin/bash
# rc_files=/etc/bash.bashrc: the conda and mamba
# activation source lines, plus 'conda activate base', are appended to the
# specified rc file exactly once.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed"                   test -f /opt/conda/bin/conda
check "conda --version succeeds"                 /opt/conda/bin/conda --version

# --- activation rc file was written ---
check "/etc/bash.bashrc exists"                  test -f /etc/bash.bashrc
echo "=== /etc/bash.bashrc ==="; cat /etc/bash.bashrc 2>/dev/null || echo "(missing)"

# --- conda.sh source line appended ---
check "conda.sh sourced in /etc/bash.bashrc"     grep -Fq ". '/opt/conda/etc/profile.d/conda.sh'" /etc/bash.bashrc

# --- mamba.sh source line appended ---
check "mamba.sh sourced in /etc/bash.bashrc"     grep -Fq ". '/opt/conda/etc/profile.d/mamba.sh'" /etc/bash.bashrc

# --- conda activate line appended (active_env defaults to 'base') ---
check "conda activate base in /etc/bash.bashrc"  grep -Fq "conda activate base" /etc/bash.bashrc

# --- idempotency: line appears exactly once ---
check "conda.sh line not duplicated"             bash -c '[ "$(grep -Fc ". '"'"'/opt/conda/etc/profile.d/conda.sh'"'"'" /etc/bash.bashrc)" -eq 1 ]'
check "activate line not duplicated"             bash -c '[ "$(grep -Fc "conda activate base" /etc/bash.bashrc)" -eq 1 ]'

reportResults
