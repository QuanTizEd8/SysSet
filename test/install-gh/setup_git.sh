#!/bin/bash
# setup_git=true + add_remote_user_config=true (vscode user, default git_hostname=github.com).
# Verifies gh auth setup-git wrote the credential helper lines to ~/.gitconfig.
set -e

source dev-container-features-test-lib

# --- gh installed ---
check "gh on PATH" command -v gh
check "gh --version succeeds" gh --version

# --- .gitconfig written for vscode user ---
echo "=== /home/vscode/.gitconfig ==="
cat /home/vscode/.gitconfig 2> /dev/null || echo "(missing)"

check ".gitconfig exists for vscode user" test -f /home/vscode/.gitconfig
# gh auth setup-git --force writes:
#   [credential "https://github.com"]
#     helper =
#     helper = !gh auth git-credential
check ".gitconfig contains gh auth git-credential helper" bash -c \
  'grep -q "gh auth git-credential" /home/vscode/.gitconfig 2>/dev/null'
check ".gitconfig has github.com credential section" bash -c \
  'git config --file /home/vscode/.gitconfig --get-all \
     credential."https://github.com".helper 2>/dev/null | grep -q "gh auth git-credential"'
check ".gitconfig owned by vscode" bash -c \
  '[ "$(stat -c %U /home/vscode/.gitconfig 2>/dev/null)" = "vscode" ]'

reportResults
