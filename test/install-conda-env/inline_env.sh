#!/bin/bash
# env_name=myenv, packages="numpy pandas": an inline named environment is
# created from package names without a YAML file.  Verifies the environment
# exists, the requested packages are importable, and the base env is untouched.
set -e

source dev-container-features-test-lib

# --- environment exists ---
check "myenv environment is listed"           /opt/conda/bin/conda env list
check "myenv directory exists"                test -d /opt/conda/envs/myenv
check "myenv python binary exists"            test -f /opt/conda/envs/myenv/bin/python
check "myenv pip binary exists"               test -f /opt/conda/envs/myenv/bin/pip

# --- packages installed ---
check "numpy importable in myenv"             /opt/conda/envs/myenv/bin/python -c 'import numpy'
check "pandas importable in myenv"            /opt/conda/envs/myenv/bin/python -c 'import pandas'

# --- base env untouched ---
check "base env still exists"                 test -d /opt/conda

# --- conda cache cleaned (no_cache_clean=false by default) ---
check "conda pkgs cache is small after clean" bash -c 'du -sh /opt/conda/pkgs 2>/dev/null; true'

reportResults
