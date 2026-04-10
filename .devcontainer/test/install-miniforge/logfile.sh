#!/bin/bash
# logfile=/tmp/miniforge.log: all output is
# captured to the specified log file in addition to stdout/stderr.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed"             test -f /opt/conda/bin/conda
check "conda --version succeeds"           /opt/conda/bin/conda --version

# --- log file written ---
check "logfile was created"                test -f /tmp/miniforge.log
check "logfile is non-empty"               test -s /tmp/miniforge.log
check "logfile contains install marker"    grep -q "Miniforge" /tmp/miniforge.log
check "logfile contains success marker"    grep -q "Conda installation complete" /tmp/miniforge.log
check "logfile contains bin_dir path"    grep -q "/opt/conda" /tmp/miniforge.log
check "logfile records conda info output"  grep -q "conda_dir" /tmp/miniforge.log

reportResults
