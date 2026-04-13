#!/usr/bin/env bash
# no_install_from_api: with no_install_from_api=true, enforce_options must write
# an HOMEBREW_NO_INSTALL_FROM_API=1 export block to each user init file.
# A second run with the default (no_install_from_api=false) must remove that block.
#
# Brew is pre-installed (if_exists=skip).
#
# Cleanup: removes both the shellenv block and the no_install_from_api block
# from all user init files on EXIT.
set -e

REPO_ROOT="$1"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

_HOME="$HOME"
_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"

_cleanup() {
  block_cleanup_all "brew shellenv (install-homebrew)"
  block_cleanup_all "HOMEBREW_NO_INSTALL_FROM_API (install-homebrew)"
}
trap _cleanup EXIT

# ── First run: no_install_from_api=true ──────────────────────────────────────
echo "=== First run: no_install_from_api=true ==="
bash "${REPO_ROOT}/src/install-homebrew/install.sh" \
  --no_install_from_api true

# --- brew is intact ---
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- HOMEBREW_NO_INSTALL_FROM_API=1 block written to user init files ---
echo "=== ~/.zprofile (after first run) ==="
cat "${_HOME}/.zprofile" 2> /dev/null || echo "(missing)"
echo "=== ~/.bashrc (after first run) ==="
tail -20 "${_HOME}/.bashrc" 2> /dev/null || echo "(missing)"

check "a user dotfile has NO_INSTALL_FROM_API begin marker" \
  bash -c 'grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" ~/.bash_profile 2>/dev/null ||
             grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" ~/.bash_login  2>/dev/null ||
             grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" ~/.profile      2>/dev/null ||
             grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" ~/.bashrc       2>/dev/null ||
             grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" ~/.zprofile     2>/dev/null ||
             grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" ~/.zshrc        2>/dev/null'
check "a user dotfile exports HOMEBREW_NO_INSTALL_FROM_API=1" \
  bash -c 'grep -qF "HOMEBREW_NO_INSTALL_FROM_API=1" ~/.bash_profile 2>/dev/null ||
             grep -qF "HOMEBREW_NO_INSTALL_FROM_API=1" ~/.bash_login  2>/dev/null ||
             grep -qF "HOMEBREW_NO_INSTALL_FROM_API=1" ~/.profile      2>/dev/null ||
             grep -qF "HOMEBREW_NO_INSTALL_FROM_API=1" ~/.bashrc       2>/dev/null ||
             grep -qF "HOMEBREW_NO_INSTALL_FROM_API=1" ~/.zprofile     2>/dev/null ||
             grep -qF "HOMEBREW_NO_INSTALL_FROM_API=1" ~/.zshrc        2>/dev/null'

# ── Second run: no_install_from_api=false (default) — block must be removed ──
echo "=== Second run: no_install_from_api=false (default) ==="
bash "${REPO_ROOT}/src/install-homebrew/install.sh"

echo "=== ~/.zprofile (after second run) ==="
cat "${_HOME}/.zprofile" 2> /dev/null || echo "(missing)"

check "NO_INSTALL_FROM_API block absent from ~/.bash_profile after second run" \
  bash -c '! grep -qF "HOMEBREW_NO_INSTALL_FROM_API" ~/.bash_profile 2>/dev/null'
check "NO_INSTALL_FROM_API block absent from ~/.bashrc after second run" \
  bash -c '! grep -qF "HOMEBREW_NO_INSTALL_FROM_API" ~/.bashrc 2>/dev/null'
check "NO_INSTALL_FROM_API block absent from ~/.zprofile after second run" \
  bash -c '! grep -qF "HOMEBREW_NO_INSTALL_FROM_API" ~/.zprofile 2>/dev/null'
check "NO_INSTALL_FROM_API block absent from ~/.zshrc after second run" \
  bash -c '! grep -qF "HOMEBREW_NO_INSTALL_FROM_API" ~/.zshrc 2>/dev/null'

reportResults
