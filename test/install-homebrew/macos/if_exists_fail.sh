#!/usr/bin/env bash
# shellcheck disable=SC2088  # ~/ in check labels is intentional (display only)
# if_exists_fail: if_exists=fail when brew is pre-installed must exit non-zero.
# No dotfiles are touched (the installer exits before export_shellenv_main).
set -e

REPO_ROOT="$1"
source "${REPO_ROOT}/test/lib/assert.sh"

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"

# --- brew is present (pre-condition) ---
check "brew is present (pre-condition)" test -f "$_BREW"

# --- feature must exit non-zero ---
fail_check "if_exists=fail exits non-zero when brew is already installed" \
  bash "${REPO_ROOT}/src/install-homebrew/install.sh" --if_exists fail

# --- brew is still intact (uninstall was NOT triggered) ---
check "brew binary still present after fail" test -f "$_BREW"
check "brew --version still succeeds after fail" "$_BREW" --version

# --- no dotfiles were written (installer exited before export step) ---
check "~/.zprofile has NO brew marker" \
  bash -c '! grep -qF "brew shellenv (install-homebrew)" ~/.zprofile 2>/dev/null'

reportResults
