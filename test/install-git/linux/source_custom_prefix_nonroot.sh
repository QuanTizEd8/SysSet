#!/usr/bin/env bash
# Verify the non-root install path: when install.bash is run as a non-root user
# with a custom prefix, it creates a ~/.local/bin/git symlink instead of writing
# to /usr/local/bin (which requires root).
#
# SETUP_CMD (in source_custom_prefix_nonroot.conf) pre-installs all build deps
# as root and creates the vscode user with a writable /opt/git directory.
# The scenario then runs as vscode via RUN_AS=vscode.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

# Confirm the scenario is running as a non-root user.
check "running as non-root user" bash -c '[ "$(id -u)" != "0" ]'

# Run the feature as the non-root user.
bash "${REPO_ROOT}/src/install-git/install.bash" \
  --method source \
  --prefix /opt/git \
  --version stable

# Assertions: git installed to prefix, symlink in ~/.local/bin, NOT in /usr/local/bin.
check "git binary at /opt/git/bin/git" test -x /opt/git/bin/git
check "git --version succeeds" /opt/git/bin/git --version
check "~/.local/bin/git symlink created" test -L "${HOME}/.local/bin/git"
check "~/.local/bin/git resolves to /opt/git/bin/git" \
  bash -c '[ "$(readlink -f "${HOME}/.local/bin/git")" = "$(readlink -f /opt/git/bin/git)" ]'
check "no /usr/local/bin/git symlink created" bash -c '! test -e /usr/local/bin/git'

reportResults
