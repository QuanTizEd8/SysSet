#!/bin/bash
# if_exists=update, no pre-existing conda (ubuntu:latest): with no existing
# conda installation the if_exists check is not triggered and Miniforge installs
# normally.  This verifies the option is accepted and does not break a fresh
# install.  The 'update' path itself (pre-existing conda + if_exists=update)
# exits non-zero ("not yet implemented"), which causes the image build to fail
# before the test script can run — so it cannot be tested as a devcontainer
# scenario at this time.
set -e

source dev-container-features-test-lib

# --- fresh install succeeded ---
check "conda directory exists"             test -d /opt/conda
check "conda binary installed"             test -f /opt/conda/bin/conda
check "conda binary is executable"         test -x /opt/conda/bin/conda
check "mamba binary installed"             test -f /opt/conda/bin/mamba
check "mamba binary is executable"         test -x /opt/conda/bin/mamba

# --- conda is functional ---
check "conda --version succeeds"           /opt/conda/bin/conda --version
check "mamba --version succeeds"           /opt/conda/bin/mamba --version
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'

reportResults
