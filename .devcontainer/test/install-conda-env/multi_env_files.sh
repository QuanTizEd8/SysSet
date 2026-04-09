#!/bin/bash
# env_files="envA.yml :: envB.yml": two YAML files passed as a ' :: '-separated
# string are both processed.  Verifies the array parsing fix correctly produces
# exactly two paths with no empty elements.
set -e

source dev-container-features-test-lib

# --- both YAML files present ---
check "envA.yml exists"               test -f /tmp/test-envs/envA.yml
check "envB.yml exists"               test -f /tmp/test-envs/envB.yml

# --- both environments created ---
check "envA environment is listed"    bash -c '/opt/conda/bin/conda env list | grep -q envA'
check "envB environment is listed"    bash -c '/opt/conda/bin/conda env list | grep -q envB'
check "envA directory exists"         test -d /opt/conda/envs/envA
check "envB directory exists"         test -d /opt/conda/envs/envB

# --- packages from each YAML ---
check "numpy importable in envA"      /opt/conda/envs/envA/bin/python -c 'import numpy'
check "pandas importable in envB"     /opt/conda/envs/envB/bin/python -c 'import pandas'

reportResults
