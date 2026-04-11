#!/usr/bin/env bash
# export_path_idempotent: run the feature twice with export_path=auto.
# The second run must update the shellenv blocks in-place without appending
# a duplicate — each begin marker must appear exactly once per file.
#
# Cleanup: removes shellenv blocks from all four user dotfiles on EXIT.
set -e

REPO_ROOT="$1"
source "${REPO_ROOT}/test/lib/macos-test-lib.sh"

_BREW_PREFIX="$(brew --prefix 2>/dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_HOME="$HOME"

_cleanup() {
  for f in "${_HOME}/.bash_profile" "${_HOME}/.bash_login" "${_HOME}/.profile" \
            "${_HOME}/.bashrc" "${_HOME}/.zprofile" "${_HOME}/.zshrc"; do
    shellenv_block_cleanup "$f"
  done
}
trap _cleanup EXIT

# First run
bash "${REPO_ROOT}/src/install-homebrew/scripts/install.sh"
# Second run (idempotency check)
bash "${REPO_ROOT}/src/install-homebrew/scripts/install.sh"

# --- brew is intact ---
check "brew binary present"              test -f "$_BREW"
check "brew --version succeeds"          "$_BREW" --version

# --- exactly one begin marker per file (no duplicates) ---
_count_marker() {
  local f="$1"
  [[ -f "$f" ]] || echo 0
  grep -cF '# >>> brew shellenv (install-homebrew) >>>' "$f" 2>/dev/null || echo 0
}
export -f _count_marker 2>/dev/null || true

check "~/.bash_profile has exactly one begin marker" \
    bash -c '[[ "$({ grep -cF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_profile 2>/dev/null || echo 0; })" -eq 1 ]]'
check "~/.bashrc has exactly one begin marker" \
    bash -c '[[ "$({ grep -cF "# >>> brew shellenv (install-homebrew) >>>" ~/.bashrc        2>/dev/null || echo 0; })" -eq 1 ]]'
check "~/.zprofile has exactly one begin marker" \
    bash -c '[[ "$({ grep -cF "# >>> brew shellenv (install-homebrew) >>>" ~/.zprofile      2>/dev/null || echo 0; })" -eq 1 ]]'
check "~/.zshrc has exactly one begin marker" \
    bash -c '[[ "$({ grep -cF "# >>> brew shellenv (install-homebrew) >>>" ~/.zshrc         2>/dev/null || echo 0; })" -eq 1 ]]'

echo "=== ~/.zprofile ==="; cat "${_HOME}/.zprofile" 2>/dev/null || echo "(missing)"
echo "=== ~/.zshrc ===";   cat "${_HOME}/.zshrc"    2>/dev/null || echo "(missing)"

reportResults
