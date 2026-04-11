#!/bin/bash
# post_env_script=/tmp/post-env.sh, env_name=scriptenv: the post-env script
# receives the environment name as $1 and writes it to /tmp/post-env-ran.
# Verifies the script was actually called with the correct argument.
set -e

source dev-container-features-test-lib

# --- conda environment created ---
check "scriptenv environment is listed" bash -c '/opt/conda/bin/conda env list | grep -q scriptenv'
check "scriptenv directory exists" test -d /opt/conda/envs/scriptenv
check "numpy importable in scriptenv" /opt/conda/envs/scriptenv/bin/python -c 'import numpy'

# --- post-env script was executed ---
check "post-env sentinel file exists" test -f /tmp/post-env-ran
check "post-env script received env name" bash -c '[ "$(cat /tmp/post-env-ran)" = "scriptenv" ]'

reportResults
