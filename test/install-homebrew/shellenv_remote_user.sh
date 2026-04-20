#!/bin/bash
# shellenv_remote_user: add_remote_user=true with remoteUser="vscode".
# Verifies that per-user shellenv blocks are written to vscode's init files
# AND that system-wide blocks are still present (root installs Case A).
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew
_MARKER='brew shellenv (install-homebrew)'

# --- brew is functional ---
check "brew binary installed" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- system-wide blocks (Case A: root + Linux) ---
check "profile.d/brew.sh has shellenv marker" grep -qF "$_MARKER" /etc/profile.d/brew.sh
check "bash.bashrc has shellenv marker" grep -qF "$_MARKER" /etc/bash.bashrc

# --- per-user blocks for vscode ---
# Match lib/shell.sh shell__user_login_file: Debian/Ubuntu skel uses ~/.profile
# when ~/.bash_profile is absent.
_VSCODE_HOME=/home/vscode
_VSCODE_LOGIN=""
for _f in "${_VSCODE_HOME}/.bash_profile" "${_VSCODE_HOME}/.bash_login" "${_VSCODE_HOME}/.profile"; do
  if [ -f "$_f" ]; then
    _VSCODE_LOGIN="$_f"
    break
  fi
done
[ -z "$_VSCODE_LOGIN" ] && _VSCODE_LOGIN="${_VSCODE_HOME}/.bash_profile"

echo "=== /home/vscode init files (bash login: ${_VSCODE_LOGIN}) ==="
for f in .bash_profile .bash_login .profile .bashrc .zprofile .zshrc; do
  echo "--- $f ---"
  cat "${_VSCODE_HOME}/$f" 2> /dev/null || echo "(missing)"
done

check "vscode bash login file has shellenv marker" grep -qF "$_MARKER" "$_VSCODE_LOGIN"
check "vscode .bashrc has shellenv marker" grep -qF "$_MARKER" "${_VSCODE_HOME}/.bashrc"
check "vscode .zprofile has shellenv marker" grep -qF "$_MARKER" "${_VSCODE_HOME}/.zprofile"
check "vscode .zshrc has shellenv marker" grep -qF "$_MARKER" "${_VSCODE_HOME}/.zshrc"

check "vscode bash login file has brew shellenv eval" grep -qF 'brew shellenv' "$_VSCODE_LOGIN"
check "vscode .bashrc has brew shellenv eval" grep -qF 'brew shellenv' "${_VSCODE_HOME}/.bashrc"

# --- files owned by vscode ---
check "vscode bash login file owned by vscode" bash -c '[ "$(stat -c %U "$0")" = vscode ]' "$_VSCODE_LOGIN"
check "vscode .bashrc owned by vscode" bash -c '[ "$(stat -c %U "$0")" = vscode ]' "${_VSCODE_HOME}/.bashrc"

reportResults
