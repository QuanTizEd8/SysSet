#!/bin/bash
# if_exists=update, no pre-existing conda (ubuntu:latest): with no existing
# conda installation the if_exists check is not triggered and Miniforge installs
# normally.  This verifies the option is accepted and does not break a fresh
# install.  See if_exists_update_preinstall for the actual update path test
# (pre-existing conda + if_exists=update → conda updated in-place).
set -e

source dev-container-features-test-lib

# --- fresh install succeeded ---
check "conda directory exists" test -d /opt/conda
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda
check "mamba binary installed" test -f /opt/conda/bin/mamba
check "mamba binary is executable" test -x /opt/conda/bin/mamba

# --- conda is functional ---
echo "=== conda --version ==="
/opt/conda/bin/conda --version 2>&1 || echo "(failed)"
check "conda --version succeeds" /opt/conda/bin/conda --version
check "mamba --version succeeds" /opt/conda/bin/mamba --version
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'

reportResults
