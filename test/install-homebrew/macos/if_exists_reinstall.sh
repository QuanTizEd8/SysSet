#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # bash -c literal script, ~/ in labels
# if_exists_reinstall: Homebrew is already installed (by the runner or the
# preceding fresh_install scenario).  Running the feature with if_exists=reinstall
# must uninstall then reinstall Homebrew from scratch and then run post-install
# steps (shellenv export).
#
# Cleanup: removes shellenv blocks from user dotfiles on EXIT.
set -e

REPO_ROOT="$1"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

_HOME="$HOME"

_cleanup() {
  block_cleanup_all "brew shellenv (install-homebrew)"
}
trap _cleanup EXIT

# ── Pre-condition: brew is present ────────────────────────────────────────────
_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
check "brew present before reinstall (pre-condition)" test -f "$_BREW"

# ── Run the feature with if_exists=reinstall ──────────────────────────────────
echo "=== Running install-homebrew with if_exists=reinstall ==="
bash "${REPO_ROOT}/src/install-homebrew/install.sh" \
  --if_exists reinstall
echo "=== Feature completed ==="
# The feature's internal uninstall+reinstall removes /opt/homebrew/bin/bash
# (installed by an earlier scenario) without reinstalling it.  Clear the
# command hash table so subsequent 'bash …' calls fall through to /bin/bash.
hash -r

# ── Verify brew is functional after reinstall ────────────────────────────────
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"

check "brew prefix directory exists after reinstall" test -d "$_BREW_PREFIX"
check "brew binary present after reinstall" test -f "$_BREW"
check "brew binary is executable after reinstall" test -x "$_BREW"
check "brew --version succeeds after reinstall" "$_BREW" --version
check "brew --version reports Homebrew" bash -c '"$1" --version | grep -q Homebrew' -- "$_BREW"

# ── Verify shellenv blocks written (Case B: non-root on macOS) ───────────────
echo "=== ~/.zprofile ==="
cat "${_HOME}/.zprofile" 2> /dev/null || echo "(missing)"

check "a login bash file has shellenv marker" \
  bash -c 'grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_profile 2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_login  2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.profile      2>/dev/null'
check "~/.zprofile has shellenv marker" \
  grep -qF '# >>> brew shellenv (install-homebrew) >>>' "${_HOME}/.zprofile"

reportResults
