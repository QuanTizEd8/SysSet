#!/usr/bin/env bash
# update_false: update=false must skip the 'brew update' step while still
# installing brew (if_exists=skip, since brew is pre-installed) and exporting
# shellenv.
#
# The logfile option is used to capture installer output so the absence of
# 'brew update' can be verified.
#
# Cleanup: removes the logfile and shellenv blocks from user dotfiles on EXIT.
set -e

REPO_ROOT="$1"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

_HOME="$HOME"
_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_LOGFILE="/tmp/brew-update-false-test-$$.log"

_cleanup() {
  rm -f "$_LOGFILE"
  block_cleanup_all "brew shellenv (install-homebrew)"
}
trap _cleanup EXIT

# --- run the feature with update=false and a logfile ---
bash "${REPO_ROOT}/src/install-homebrew/install.sh" \
  --update false \
  --logfile "$_LOGFILE"

# --- brew is intact (if_exists=skip) ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew binary present" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- shellenv still written (export_path=auto by default) ---
check "a user dotfile has shellenv marker" \
  bash -c 'grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_profile 2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_login  2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.profile      2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bashrc       2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.zprofile     2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.zshrc        2>/dev/null'

# --- brew update was NOT run (logfile must not contain the update completion marker) ---
echo "===== ${_LOGFILE} (last 30 lines) ====="
tail -30 "$_LOGFILE" 2> /dev/null || echo "(missing)"
check "logfile was created" test -f "$_LOGFILE"
check "logfile is non-empty" test -s "$_LOGFILE"
check "brew update NOT run" \
  bash -c '! grep -q "brew update completed" "'"$_LOGFILE"'"'
check "install completed successfully" \
  grep -q "Homebrew installation complete" "$_LOGFILE"

reportResults
