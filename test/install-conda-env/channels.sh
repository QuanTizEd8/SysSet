#!/bin/bash
# channels="conda-forge :: defaults", env_name=chanenv, packages=numpy:
# both channels are added to the conda config before the environment is
# created.  Verifies that channels appear in the active conda configuration.
set -e

source dev-container-features-test-lib

# --- environment created ---
check "chanenv environment is listed" bash -c '/opt/conda/bin/conda env list | grep -q chanenv'
check "chanenv directory exists" test -d /opt/conda/envs/chanenv
check "numpy importable in chanenv" /opt/conda/envs/chanenv/bin/python -c 'import numpy'

# --- channels are in the conda config ---
check "conda-forge channel in conda config" bash -c '/opt/conda/bin/conda config --show channels | grep -q conda-forge'
check "defaults channel in conda config" bash -c '/opt/conda/bin/conda config --show channels | grep -q defaults'

reportResults
