#!/bin/bash
# no_cache_clean=true: 'conda clean' is skipped after environment setup.
# The packages cache directory should still be populated (not emptied).
set -e

source dev-container-features-test-lib

# --- environment created ---
check "cleanenv environment is listed"         bash -c '/opt/conda/bin/conda env list | grep -q cleanenv'
check "cleanenv directory exists"              test -d /opt/conda/envs/cleanenv
check "numpy importable in cleanenv"           /opt/conda/envs/cleanenv/bin/python -c 'import numpy'

# --- cache was NOT cleaned: pkgs dir has at least one tarball/conda file ---
check "conda pkgs directory exists"            test -d /opt/conda/pkgs
check "pkgs dir is non-empty after no_clean"   bash -c 'find /opt/conda/pkgs -maxdepth 1 -name "*.conda" -o -name "*.tar.bz2" | grep -q .'

reportResults
