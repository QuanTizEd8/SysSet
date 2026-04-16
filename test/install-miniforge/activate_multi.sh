#!/bin/bash
# rc_files="/root/.bashrc\n/etc/bash.bashrc": conda init block is written
# to both rc files, verifying the newline separator is correctly parsed.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- both rc files exist ---
check "/root/.bashrc exists" test -f /root/.bashrc
check "/etc/bash.bashrc exists" test -f /etc/bash.bashrc
echo "=== /root/.bashrc ==="
cat /root/.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"

# --- our idempotency block markers are present in /root/.bashrc ---
check "miniforge begin marker in /root/.bashrc" grep -Fq "# >>> conda init (install-miniforge) >>>" /root/.bashrc
check "conda initialize begin marker in /root/.bashrc" grep -Fq "# >>> conda initialize >>>" /root/.bashrc

# --- our idempotency block markers are present in /etc/bash.bashrc ---
check "miniforge begin marker in /etc/bash.bashrc" grep -Fq "# >>> conda init (install-miniforge) >>>" /etc/bash.bashrc
check "conda initialize begin marker in /etc/bash.bashrc" grep -Fq "# >>> conda initialize >>>" /etc/bash.bashrc

# --- neither file has duplicated markers ---
check "no dup miniforge marker in /root/.bashrc" bash -c '[ "$(grep -Fc "# >>> conda init (install-miniforge) >>>" /root/.bashrc)" -eq 1 ]'
check "no dup miniforge marker in /etc/bash.bashrc" bash -c '[ "$(grep -Fc "# >>> conda init (install-miniforge) >>>" /etc/bash.bashrc)" -eq 1 ]'

reportResults
