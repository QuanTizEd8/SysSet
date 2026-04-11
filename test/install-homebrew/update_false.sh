#!/bin/bash
# update_false: update=false disables the post-install 'brew update' run.
# Verifies that Homebrew still installs and is functional even without the
# index update step.
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- brew installed and functional ---
check "brew binary installed" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds" "$_BREW" --version
check "brew --version reports Homebrew" bash -c '"$1" --version | grep -q Homebrew' -- "$_BREW"

# --- shellenv still exported (export_path=auto by default) ---
check "profile.d/brew.sh written" test -f /etc/profile.d/brew.sh
check "profile.d/brew.sh has marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/profile.d/brew.sh

reportResults
