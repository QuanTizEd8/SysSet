#!/bin/bash
# logfile=/tmp/conda-env.log: all script output is captured to the log file.
# Verifies the file is created, is non-empty, and contains expected markers.
set -e

source dev-container-features-test-lib

# --- conda environment created ---
check "logenv environment is listed" bash -c '/opt/conda/bin/conda env list | grep -q logenv'
check "logenv directory exists" test -d /opt/conda/envs/logenv

# --- log file written ---
check "logfile was created" test -f /tmp/conda-env.log
check "logfile is non-empty" test -s /tmp/conda-env.log
check "logfile contains env name" grep -q "logenv" /tmp/conda-env.log
check "logfile contains success marker" grep -q "Conda environment setup complete" /tmp/conda-env.log

reportResults
