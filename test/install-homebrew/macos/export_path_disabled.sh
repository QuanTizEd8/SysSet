#!/usr/bin/env bash
# shellcheck disable=SC2088  # ~/ in check labels is intentional (display only)
# export_path_disabled: export_path="" skips all shellenv writes.
# Verifies that brew is intact (if_exists=skip) and that no dotfiles are touched.
set -e

REPO_ROOT="$1"
source "${REPO_ROOT}/test/lib/macos-test-lib.sh"

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"

# No cleanup needed: this scenario must not write to any file.

# --- run the feature ---
bash "${REPO_ROOT}/src/install-homebrew/install.sh" --export_path ""

# --- brew is intact ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- no shellenv blocks written to any file ---
check "~/.bash_profile has NO brew marker" \
  bash -c '! grep -qF "brew shellenv (install-homebrew)" ~/.bash_profile 2>/dev/null'
check "~/.bashrc has NO brew marker" \
  bash -c '! grep -qF "brew shellenv (install-homebrew)" ~/.bashrc 2>/dev/null'
check "~/.zprofile has NO brew marker" \
  bash -c '! grep -qF "brew shellenv (install-homebrew)" ~/.zprofile 2>/dev/null'
check "~/.zshrc has NO brew marker" \
  bash -c '! grep -qF "brew shellenv (install-homebrew)" ~/.zshrc 2>/dev/null'
check "profile.d/brew.sh NOT written" \
  bash -c '! test -f /etc/profile.d/brew.sh'

reportResults
