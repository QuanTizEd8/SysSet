#!/bin/bash
# env_dirs=/tmp/test-envs: all YAML files discovered in the directory are
# processed.  The Dockerfile places two YAMLs (direnv1, direnv2) so both
# environments should be created.
set -e

source dev-container-features-test-lib

# --- both YAML files are in place ---
check "direnv1.yml exists"                   test -f /tmp/test-envs/direnv1.yml
check "direnv2.yml exists"                   test -f /tmp/test-envs/direnv2.yml

# --- both environments created ---
check "direnv1 environment is listed"        bash -c '/opt/conda/bin/conda env list | grep -q direnv1'
check "direnv2 environment is listed"        bash -c '/opt/conda/bin/conda env list | grep -q direnv2'
check "direnv1 directory exists"             test -d /opt/conda/envs/direnv1
check "direnv2 directory exists"             test -d /opt/conda/envs/direnv2

# --- packages installed from each YAML ---
check "numpy importable in direnv1"          /opt/conda/envs/direnv1/bin/python -c 'import numpy'
check "pandas importable in direnv2"         /opt/conda/envs/direnv2/bin/python -c 'import pandas'

reportResults
