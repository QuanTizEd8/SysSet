#!/bin/bash
# if_exists_skip: Homebrew is pre-installed in the image (see Dockerfile).
# The feature detects the existing installation, skips the installer, and
# proceeds to post-install steps (shellenv export).
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- original Homebrew installation is intact ---
check "linuxbrew prefix directory exists" test -d /home/linuxbrew/.linuxbrew
check "brew binary present" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"

# --- brew is still functional ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds" "$_BREW" --version
check "brew --version reports Homebrew" bash -c '"$_BREW" --version | grep -q Homebrew' _BREW="$_BREW"

# --- post-install steps ran (shellenv export written by feature) ---
echo "=== /etc/profile.d/brew.sh ==="
cat /etc/profile.d/brew.sh 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc (tail) ==="
tail -10 /etc/bash.bashrc 2> /dev/null || echo "(missing)"
check "profile.d/brew.sh written" test -f /etc/profile.d/brew.sh
check "profile.d/brew.sh has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/profile.d/brew.sh
check "bash.bashrc has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/bash.bashrc

reportResults
