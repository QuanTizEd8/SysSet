#!/bin/bash
# if_exists_reinstall: Homebrew is pre-installed in the image (see Dockerfile).
# The feature is configured with if_exists=reinstall, which uninstalls and then
# reinstalls Homebrew fresh, then runs post-install steps (shellenv export).
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- Homebrew was reinstalled and is intact ---
check "linuxbrew prefix directory exists" test -d /home/linuxbrew/.linuxbrew
check "brew binary present" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"

# --- brew is functional after reinstall ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds" "$_BREW" --version
check "brew --version reports Homebrew" bash -c '"$1" --version | grep -q Homebrew' -- "$_BREW"

# --- post-install steps ran (shellenv export written by feature) ---
echo "=== /etc/profile.d/brew.sh ==="
cat /etc/profile.d/brew.sh 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc (tail) ==="
tail -10 /etc/bash.bashrc 2> /dev/null || echo "(missing)"
check "profile.d/brew.sh written" test -f /etc/profile.d/brew.sh
check "profile.d/brew.sh has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/profile.d/brew.sh
check "bash.bashrc has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/bash.bashrc

reportResults
