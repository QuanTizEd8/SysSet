#!/bin/bash
# download=true, install=true, activates="/root/.bashrc :: /etc/bash.bashrc":
# activation lines are appended to both rc files, verifying the ' :: ' array
# separator is correctly parsed from the env-var-mode input.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed"                    test -f /opt/conda/bin/conda
check "conda --version succeeds"                  /opt/conda/bin/conda --version

# --- both rc files exist ---
check "/root/.bashrc exists"                      test -f /root/.bashrc
check "/etc/bash.bashrc exists"                   test -f /etc/bash.bashrc

# --- conda.sh sourced in /root/.bashrc ---
check "conda.sh sourced in /root/.bashrc"         grep -Fq ". '/opt/conda/etc/profile.d/conda.sh'" /root/.bashrc
check "mamba.sh sourced in /root/.bashrc"         grep -Fq ". '/opt/conda/etc/profile.d/mamba.sh'" /root/.bashrc
check "conda activate base in /root/.bashrc"      grep -Fq "conda activate base" /root/.bashrc

# --- conda.sh sourced in /etc/bash.bashrc ---
check "conda.sh sourced in /etc/bash.bashrc"      grep -Fq ". '/opt/conda/etc/profile.d/conda.sh'" /etc/bash.bashrc
check "mamba.sh sourced in /etc/bash.bashrc"      grep -Fq ". '/opt/conda/etc/profile.d/mamba.sh'" /etc/bash.bashrc
check "conda activate base in /etc/bash.bashrc"   grep -Fq "conda activate base" /etc/bash.bashrc

# --- neither file has duplicated lines ---
check "no dup conda.sh line in /root/.bashrc"     bash -c '[ "$(grep -Fc ". '"'"'/opt/conda/etc/profile.d/conda.sh'"'"'" /root/.bashrc)" -eq 1 ]'
check "no dup conda.sh line in /etc/bash.bashrc"  bash -c '[ "$(grep -Fc ". '"'"'/opt/conda/etc/profile.d/conda.sh'"'"'" /etc/bash.bashrc)" -eq 1 ]'

reportResults
