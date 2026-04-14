#!/bin/bash
# setup_git=true + git_hostname=git.corp.example.com + add_remote_user_config=true (vscode user).
# Verifies gh auth setup-git wrote the credential helper for the custom GHES hostname.
set -e

source dev-container-features-test-lib

# --- gh installed ---
check "gh on PATH" command -v gh
check "gh --version succeeds" gh --version

# --- .gitconfig written for vscode user ---
echo "=== /home/vscode/.gitconfig ==="
cat /home/vscode/.gitconfig 2> /dev/null || echo "(missing)"

check ".gitconfig exists for vscode user" test -f /home/vscode/.gitconfig
check ".gitconfig contains gh auth git-credential for GHES host" bash -c \
  'grep -q "gh auth git-credential" /home/vscode/.gitconfig 2>/dev/null'
check ".gitconfig has GHES credential section" bash -c \
  'git config --file /home/vscode/.gitconfig --get-all \
     credential."https://git.corp.example.com".helper 2>/dev/null | grep -q "gh auth git-credential"'
check ".gitconfig owned by vscode" bash -c \
  '[ "$(stat -c %U /home/vscode/.gitconfig 2>/dev/null)" = "vscode" ]'

reportResults
