#!/bin/bash
# env_name=py311, python_version=3.11: an inline environment is created with a
# pinned Python version but no explicit packages (verifies the relaxed
# validation — python_version alone is enough to justify creating the env).
set -e

source dev-container-features-test-lib

# --- environment exists ---
check "py311 environment is listed"             bash -c '/opt/conda/bin/conda env list | grep -q py311'
check "py311 directory exists"                  test -d /opt/conda/envs/py311
check "py311 python binary exists"              test -f /opt/conda/envs/py311/bin/python

# --- correct Python version installed ---
check "Python 3.11 is installed in py311"       bash -c '/opt/conda/envs/py311/bin/python --version 2>&1 | grep -q "^Python 3\.11\."'

reportResults
