#!/usr/bin/env bash
# macOS: package + if_exists=skip (default).
#
# macOS GHA runners have git pre-installed via Xcode CLT (/usr/bin/git).
# The feature detects the existing installation and exits 0 without making
# any changes.  This validates:
#   - the feature script succeeds (exits 0) on macOS without Docker
#   - CLI argument parsing works end-to-end
#   - _git__check_exists correctly identifies git in PATH and applies skip
#
# gitconfig writes require an explicit exit-guard bypass; on this runner the
# feature exits early so ~/.config/git/config is NOT written — that is
# the documented behaviour of if_exists=skip.
set -e

REPO_ROOT="$1"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

# --- baseline: git is in PATH before the feature runs ---
check "git pre-installed on runner" command -v git
check "git --version succeeds" git --version

# --- run the feature (if_exists=skip default) ---
bash "${REPO_ROOT}/src/install-git/install.sh" \
  --method package \
  --version stable \
  --debug true

# --- git is still functional after the feature skips ---
check "git on PATH after feature run" command -v git
check "git still returns version" bash -c 'git --version | grep -qE "^git version [0-9]"'
check "skip did not write user system config" bash -c '! test -e "${HOME}/.config/git/config"'

reportResults
