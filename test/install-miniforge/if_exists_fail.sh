#!/bin/bash
# if_exists=fail, no pre-existing conda (ubuntu:latest): with no existing
# conda installation the if_exists check is not triggered and Miniforge installs
# normally.  This verifies the option is accepted and does not break a fresh
# install.  Testing the actual failure path (pre-existing conda + if_exists=fail)
# is not supported by the devcontainer test framework because a non-zero feature
# exit causes the image build to fail before the test script can run.
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
