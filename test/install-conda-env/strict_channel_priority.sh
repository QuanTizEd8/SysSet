#!/bin/bash
# strict_channel_priority=true, channels=conda-forge: channel_priority is set
# to 'strict' in the conda config in addition to adding the channel.
set -e

source dev-container-features-test-lib

# --- environment created ---
check "strictenv environment is listed" bash -c '/opt/conda/bin/conda env list | grep -q strictenv'
check "strictenv directory exists" test -d /opt/conda/envs/strictenv
check "numpy importable in strictenv" /opt/conda/envs/strictenv/bin/python -c 'import numpy'

# --- channel added ---
check "conda-forge channel in conda config" bash -c '/opt/conda/bin/conda config --show channels | grep -q conda-forge'

# --- strict priority set ---
check "channel_priority is strict" bash -c '/opt/conda/bin/conda config --show channel_priority | grep -q strict'

reportResults
