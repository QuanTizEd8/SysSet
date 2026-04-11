#!/bin/bash
# env_files pointing to an already-existing environment: the feature detects the
# existing env directory and runs 'env update' instead of 'env create'.
# The Dockerfile pre-creates 'simple' with numpy only; the YAML was then updated
# to also include pandas, so after the feature runs pandas should be importable.
set -e

source dev-container-features-test-lib

# --- environment still exists ---
check "simple environment is listed" bash -c '/opt/conda/bin/conda env list | grep -q simple'
check "simple directory exists" test -d /opt/conda/envs/simple

# --- original package still present ---
check "numpy importable after update" /opt/conda/envs/simple/bin/python -c 'import numpy'

# --- newly added package installed by the update ---
check "pandas importable after update" /opt/conda/envs/simple/bin/python -c 'import pandas'

reportResults
