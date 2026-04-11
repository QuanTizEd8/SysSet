#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # bash -c literal script, ~/ in labels
# fresh_install: uninstall the pre-installed Homebrew, then run the feature
# to install it from scratch.  This exercises the full install code path on
# macOS: net::fetch_url_file download, official installer run as a non-root
# user, and Case B shellenv export to personal dotfiles.
#
# ⚠️  This scenario is DESTRUCTIVE: it removes the GHA runner's Homebrew
# installation and reinstalls it.  Subsequent macOS scenarios in the same job
# are not affected because this scenario ends with brew reinstalled.
#
# Cleanup: removes shellenv blocks from user dotfiles on EXIT (brew itself
# stays installed so later alphabetical scenarios can use it).
set -e

REPO_ROOT="$1"
# shellcheck source=test/lib/macos-test-lib.sh
source "${REPO_ROOT}/test/lib/macos-test-lib.sh"

_HOME="$HOME"

_cleanup() {
  block_cleanup_all "brew shellenv (install-homebrew)"
}
trap _cleanup EXIT

# ── Step 1: Uninstall the pre-installed Homebrew ──────────────────────────────
echo "=== Uninstalling pre-installed Homebrew ==="
_UNINSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh"
_UNINSTALL_TMP="$(mktemp /tmp/brew_uninstall.XXXXXX.sh)"
curl -fsSL "$_UNINSTALL_URL" -o "$_UNINSTALL_TMP"
NONINTERACTIVE=1 bash "$_UNINSTALL_TMP" --force
rm -f "$_UNINSTALL_TMP"
echo "=== Uninstall complete ==="
# Clear the command hash table so that subsequent 'bash' calls search PATH
# afresh.  The parent shell is /opt/homebrew/bin/bash (installed by the prior
# scenario); after uninstall that binary is gone, so without this 'hash -r'
# all subsequent 'bash …' subcommands would fail with "No such file or
# directory" — the shell would still try the now-deleted path.
hash -r

# ── Step 2: Pre-condition: brew must be gone ──────────────────────────────────
check "brew binary absent after uninstall" \
  bash -c '! command -v brew > /dev/null 2>&1'

# ── Step 3: Run the feature (fresh install) ───────────────────────────────────
echo "=== Running install-homebrew feature (fresh install) ==="
bash "${REPO_ROOT}/src/install-homebrew/install.sh"
echo "=== Feature completed ==="

# Resolve the prefix the feature would have chosen (same logic as detect_brew_prefix).
if [[ "$(uname -m)" == "arm64" ]]; then
  _BREW_PREFIX="/opt/homebrew"
else
  _BREW_PREFIX="/usr/local"
fi
_BREW="${_BREW_PREFIX}/bin/brew"

# ── Step 4: Verify brew was installed ────────────────────────────────────────
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"

check "brew prefix directory exists" test -d "$_BREW_PREFIX"
check "brew binary installed" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"
check "brew --version succeeds" "$_BREW" --version
check "brew --version reports Homebrew" bash -c '"$_BREW" --version | grep -q Homebrew' _BREW="$_BREW"

# ── Step 5: Case B shellenv export written to user dotfiles ──────────────────
echo "=== ~/.zprofile ==="
cat "${_HOME}/.zprofile" 2> /dev/null || echo "(missing)"
echo "=== ~/.zshrc ==="
cat "${_HOME}/.zshrc" 2> /dev/null || echo "(missing)"

check "a login bash file has shellenv marker" \
  bash -c 'grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_profile 2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_login  2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.profile      2>/dev/null'
check "~/.bashrc has shellenv marker" \
  grep -qF '# >>> brew shellenv (install-homebrew) >>>' "${_HOME}/.bashrc"
check "~/.zprofile has shellenv marker" \
  grep -qF '# >>> brew shellenv (install-homebrew) >>>' "${_HOME}/.zprofile"
check "~/.zshrc has shellenv marker" \
  grep -qF '# >>> brew shellenv (install-homebrew) >>>' "${_HOME}/.zshrc"

# Shellenv block references the correct brew prefix.
check "shellenv block references correct brew prefix" \
  bash -c 'grep -qF "'"${_BREW_PREFIX}/bin/brew"'" ~/.zprofile 2>/dev/null ||
             grep -qF "'"${_BREW_PREFIX}/bin/brew"'" ~/.bash_profile 2>/dev/null'

# ── Step 6: Verify brew --prefix returns expected prefix ─────────────────────
_ACTUAL_PREFIX="$("${_BREW}" --prefix 2> /dev/null || true)"
echo "=== brew --prefix: ${_ACTUAL_PREFIX} ==="
check "brew --prefix returns expected prefix" test "$_ACTUAL_PREFIX" = "$_BREW_PREFIX"

reportResults
