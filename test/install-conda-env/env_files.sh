#!/bin/bash
# env_files=/tmp/test-envs/simple.yml: environment is created from a YAML file
# placed in the image by the Dockerfile.  Verifies the named env exists and
# that the package declared in the YAML is importable.
set -e

source dev-container-features-test-lib

# --- YAML file was present ---
check "YAML file exists"                     test -f /tmp/test-envs/simple.yml

# --- environment was created ---
check "simple environment is listed"         bash -c '/opt/conda/bin/conda env list | grep -q simple'
check "simple environment directory exists"  test -d /opt/conda/envs/simple
check "python binary exists in simple"       test -f /opt/conda/envs/simple/bin/python

# --- package from YAML is installed ---
check "numpy importable in simple"           /opt/conda/envs/simple/bin/python -c 'import numpy'

reportResults
