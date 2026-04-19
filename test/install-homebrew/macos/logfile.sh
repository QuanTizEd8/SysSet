#!/usr/bin/env bash
# logfile: logfile=/tmp/brew-macos-test.log — installer output is mirrored to
# the specified file in addition to stdout/stderr.
#
# Cleanup: removes the log file and shellenv blocks on EXIT.
set -e

REPO_ROOT="$1"
source "${REPO_ROOT}/test/lib/assert.sh"

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_HOME="$HOME"
_LOGFILE="/tmp/brew-macos-test-$$.log"

_cleanup() {
  rm -f "$_LOGFILE"
  for f in "${_HOME}/.bash_profile" "${_HOME}/.bash_login" "${_HOME}/.profile" \
    "${_HOME}/.bashrc" "${_HOME}/.zprofile" "${_HOME}/.zshrc"; do
    shellenv_block_cleanup "$f"
  done
}
trap _cleanup EXIT

# --- run the feature ---
bash "${REPO_ROOT}/src/install-homebrew/install.sh" \
  --logfile "$_LOGFILE"

# --- brew is intact ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- log file written ---
echo "===== ${_LOGFILE} (last 20 lines) ====="
tail -20 "$_LOGFILE" 2> /dev/null || echo "(missing)"
check "logfile was created" test -f "$_LOGFILE"
check "logfile is non-empty" test -s "$_LOGFILE"
check "logfile contains install-homebrew header" grep -q 'install-homebrew' "$_LOGFILE"
check "logfile contains success marker" grep -q 'Install Homebrew script finished successfully' "$_LOGFILE"
check "logfile contains brew prefix path" grep -qF "$_BREW_PREFIX" "$_LOGFILE"

reportResults
