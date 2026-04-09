#!/bin/bash
# env_name=pipenv, packages=pip, pip_requirements_files=/tmp/requirements.txt:
# after the conda env is created, pip installs packages from the requirements
# file.  The Dockerfile writes 'tomli' as the sole requirement.
set -e

source dev-container-features-test-lib

# --- conda environment created ---
check "pipenv environment is listed"           bash -c '/opt/conda/bin/conda env list | grep -q pipenv'
check "pipenv directory exists"                test -d /opt/conda/envs/pipenv
check "pip binary installed in pipenv"         test -f /opt/conda/envs/pipenv/bin/pip

# --- pip requirement installed ---
check "tomli importable in pipenv"             /opt/conda/envs/pipenv/bin/python -c 'import tomli'

reportResults
