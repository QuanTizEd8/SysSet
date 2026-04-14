#!/bin/bash
# repos install on Debian 12: uses the official GitHub CLI apt repo.
# Verifies gh is installed and callable.
set -e

source dev-container-features-test-lib

# --- binary present and callable ---
echo "=== which gh ==="
which gh 2>&1 || echo "(not on PATH)"
echo "=== gh --version ==="
gh --version 2>&1 || echo "(failed)"
check "gh on PATH" command -v gh
check "gh --version succeeds" gh --version

reportResults
