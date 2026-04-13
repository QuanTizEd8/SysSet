#!/usr/bin/env bash
# shellcheck disable=SC2088  # ~/ in check labels is intentional (display only)
# default: all options at their defaults.
#
# macOS runners have Homebrew pre-installed → if_exists=skip (default) applies.
# The runner is non-root → Case B shellenv export: blocks are written to the
# install user's personal dotfiles (~/.bash_profile, ~/.bashrc, ~/.zprofile,
# ~/.zshrc).
#
# Cleanup: removes shellenv blocks from all four dotfiles via trap on EXIT.
set -e

REPO_ROOT="$1"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_HOME="$HOME"

_cleanup() {
  for f in "${_HOME}/.bash_profile" "${_HOME}/.bash_login" "${_HOME}/.profile" \
    "${_HOME}/.bashrc" "${_HOME}/.zprofile" "${_HOME}/.zshrc"; do
    shellenv_block_cleanup "$f"
  done
}
trap _cleanup EXIT

# --- run the feature ---
bash "${REPO_ROOT}/src/install-homebrew/install.sh"

# --- brew is intact (if_exists=skip) ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew binary present" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- Case B: login bash file receives shellenv block ---
# The feature picks the first of .bash_profile / .bash_login / .profile that
# exists, or creates .bash_profile.  Check all three candidates collectively.
check "a login bash file has begin marker" \
  bash -c 'grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_profile 2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_login  2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.profile      2>/dev/null'
check "a login bash file has shellenv eval" \
  bash -c 'grep -qF "brew shellenv" ~/.bash_profile 2>/dev/null ||
             grep -qF "brew shellenv" ~/.bash_login  2>/dev/null ||
             grep -qF "brew shellenv" ~/.profile      2>/dev/null'

# --- ~/.bashrc ---
check "~/.bashrc has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' "${_HOME}/.bashrc"
check "~/.bashrc has shellenv eval" grep -qF 'brew shellenv' "${_HOME}/.bashrc"

# --- ~/.zprofile ---
check "~/.zprofile has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' "${_HOME}/.zprofile"
check "~/.zprofile has shellenv eval" grep -qF 'brew shellenv' "${_HOME}/.zprofile"

# --- ~/.zshrc ---
check "~/.zshrc has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' "${_HOME}/.zshrc"
check "~/.zshrc has shellenv eval" grep -qF 'brew shellenv' "${_HOME}/.zshrc"

# --- system-wide files NOT written (Case B, not root+Linux) ---
check "profile.d/brew.sh NOT written" bash -c '! test -f /etc/profile.d/brew.sh'

reportResults
