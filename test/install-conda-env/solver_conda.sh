#!/bin/bash
# solver=conda: forces the conda solver (bypasses mamba even though mamba is
# present in the Miniforge image).  The environment must still be created
# correctly; this test verifies behaviour is identical to the default path.
set -e

source dev-container-features-test-lib

# --- environment created despite forced conda solver ---
check "solverenv environment is listed"      bash -c '/opt/conda/bin/conda env list | grep -q solverenv'
check "solverenv directory exists"           test -d /opt/conda/envs/solverenv
check "python binary in solverenv"           test -f /opt/conda/envs/solverenv/bin/python
check "numpy importable in solverenv"        /opt/conda/envs/solverenv/bin/python -c 'import numpy'

reportResults
