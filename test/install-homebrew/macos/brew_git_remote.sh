#!/usr/bin/env bash
# brew_git_remote: brew_git_remote=<current_origin_url> must write an
# HOMEBREW_BREW_GIT_REMOTE export block to each user init file via
# enforce_options(), and a second run without the option must remove that block.
#
# The test sets brew_git_remote to the repository's current origin URL so the
# git remote set-url call is a no-op (no network action, no breakage) while
# still exercising the full enforce_options code path.
#
# Brew is pre-installed (if_exists=skip).
#
# Cleanup: removes shellenv and brew_git_remote blocks from user dotfiles.
set -e

REPO_ROOT="$1"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

_HOME="$HOME"
_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"

# Derive the Homebrew/brew git repository path (same logic as detect_brew_repository).
if [[ "$(uname -m)" == "arm64" ]]; then
  _BREW_REPO="$_BREW_PREFIX"
else
  _BREW_REPO="${_BREW_PREFIX}/Homebrew"
fi

# Use the current remote URL so the git set-url call is a safe no-op.
_REMOTE_URL="$(git -C "$_BREW_REPO" remote get-url origin 2> /dev/null ||
  echo "https://github.com/Homebrew/brew")"
echo "ℹ️  Using brew_git_remote: ${_REMOTE_URL}"

_cleanup() {
  block_cleanup_all "brew shellenv (install-homebrew)"
  block_cleanup_all "HOMEBREW_BREW_GIT_REMOTE (install-homebrew)"
}
trap _cleanup EXIT

# ── First run: brew_git_remote set ───────────────────────────────────────────
echo "=== First run: brew_git_remote='${_REMOTE_URL}' ==="
bash "${REPO_ROOT}/src/install-homebrew/install.sh" \
  --brew_git_remote "$_REMOTE_URL"

# --- brew is intact ---
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- git remote on the brew repository is still correct ---
check "brew git origin URL unchanged" bash -c \
  'git -C "'"$_BREW_REPO"'" remote get-url origin | grep -qF "'"$_REMOTE_URL"'"'

# --- HOMEBREW_BREW_GIT_REMOTE block written to at least one user init file ---
echo "=== ~/.zprofile (after first run) ==="
cat "${_HOME}/.zprofile" 2> /dev/null || echo "(missing)"
echo "=== ~/.bashrc (after first run, last 20 lines) ==="
tail -20 "${_HOME}/.bashrc" 2> /dev/null || echo "(missing)"

check "a user dotfile has BREW_GIT_REMOTE begin marker" \
  bash -c 'grep -qF "# >>> HOMEBREW_BREW_GIT_REMOTE (install-homebrew) >>>" ~/.bash_profile 2>/dev/null ||
             grep -qF "# >>> HOMEBREW_BREW_GIT_REMOTE (install-homebrew) >>>" ~/.bash_login  2>/dev/null ||
             grep -qF "# >>> HOMEBREW_BREW_GIT_REMOTE (install-homebrew) >>>" ~/.profile      2>/dev/null ||
             grep -qF "# >>> HOMEBREW_BREW_GIT_REMOTE (install-homebrew) >>>" ~/.bashrc       2>/dev/null ||
             grep -qF "# >>> HOMEBREW_BREW_GIT_REMOTE (install-homebrew) >>>" ~/.zprofile     2>/dev/null ||
             grep -qF "# >>> HOMEBREW_BREW_GIT_REMOTE (install-homebrew) >>>" ~/.zshrc        2>/dev/null'
check "a user dotfile exports HOMEBREW_BREW_GIT_REMOTE" \
  bash -c 'grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.bash_profile 2>/dev/null ||
             grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.bash_login  2>/dev/null ||
             grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.profile      2>/dev/null ||
             grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.bashrc       2>/dev/null ||
             grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.zprofile     2>/dev/null ||
             grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.zshrc        2>/dev/null'

# ── Second run: brew_git_remote unset (default) — block must be removed ───────
echo "=== Second run: brew_git_remote unset ==="
bash "${REPO_ROOT}/src/install-homebrew/install.sh"

echo "=== ~/.zprofile (after second run) ==="
cat "${_HOME}/.zprofile" 2> /dev/null || echo "(missing)"

check "BREW_GIT_REMOTE block absent from ~/.bash_profile after second run" \
  bash -c '! grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.bash_profile 2>/dev/null'
check "BREW_GIT_REMOTE block absent from ~/.bashrc after second run" \
  bash -c '! grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.bashrc 2>/dev/null'
check "BREW_GIT_REMOTE block absent from ~/.zprofile after second run" \
  bash -c '! grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.zprofile 2>/dev/null'
check "BREW_GIT_REMOTE block absent from ~/.zshrc after second run" \
  bash -c '! grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.zshrc 2>/dev/null'

reportResults
