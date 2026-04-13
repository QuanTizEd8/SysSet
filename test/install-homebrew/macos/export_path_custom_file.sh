#!/usr/bin/env bash
# shellcheck disable=SC2088  # ~/ in check labels is intentional (display only)
# export_path_custom_file: export_path="/tmp/test-brew-custom.sh"
# Verifies the shellenv block is written only to the specified file and that
# no personal dotfiles are touched.
#
# Cleanup: removes the custom file on EXIT.
set -e

REPO_ROOT="$1"
source "${REPO_ROOT}/test/lib/assert.sh"

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_CUSTOM_FILE="/tmp/test-brew-custom-$$.sh"

_cleanup() {
  rm -f "$_CUSTOM_FILE"
}
trap _cleanup EXIT

# --- run the feature ---
bash "${REPO_ROOT}/src/install-homebrew/install.sh" \
  --export_path "$_CUSTOM_FILE"

# --- brew is intact ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- shellenv block written to the custom file ---
echo "=== ${_CUSTOM_FILE} ==="
cat "$_CUSTOM_FILE" 2> /dev/null || echo "(missing)"
check "custom file written" test -f "$_CUSTOM_FILE"
check "custom file has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' "$_CUSTOM_FILE"
check "custom file has end marker" grep -qF '# <<< brew shellenv (install-homebrew) <<<' "$_CUSTOM_FILE"
check "custom file has shellenv eval" grep -qF 'brew shellenv' "$_CUSTOM_FILE"
check "custom file references correct brew prefix" grep -qF "${_BREW_PREFIX}/bin/brew" "$_CUSTOM_FILE"

# --- personal dotfiles NOT touched ---
check "~/.bash_profile has NO brew marker" \
  bash -c '! grep -qF "brew shellenv (install-homebrew)" ~/.bash_profile 2>/dev/null'
check "~/.zprofile has NO brew marker" \
  bash -c '! grep -qF "brew shellenv (install-homebrew)" ~/.zprofile     2>/dev/null'
check "~/.zshrc has NO brew marker" \
  bash -c '! grep -qF "brew shellenv (install-homebrew)" ~/.zshrc        2>/dev/null'

reportResults
