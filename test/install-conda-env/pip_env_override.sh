#!/bin/bash
# env_name=pipenv, packages=pip, pip_requirements_files=/tmp/requirements.txt,
# pip_env=pipenv: explicit pip_env override that equals the only env — validates
# that pip_env is honoured and the package still arrives in the right place.
set -e

source dev-container-features-test-lib

# --- conda environment created ---
check "pipenv environment is listed"           bash -c '/opt/conda/bin/conda env list | grep -q pipenv'
check "pipenv directory exists"                test -d /opt/conda/envs/pipenv
check "pip binary installed in pipenv"         test -f /opt/conda/envs/pipenv/bin/pip

# --- pip requirement installed into the explicit pip_env target ---
check "tomli importable in pipenv"             /opt/conda/envs/pipenv/bin/python -c 'import tomli'

reportResults
