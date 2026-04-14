#!/bin/bash
# sign_commits=ssh + add_remote_user_config=true (vscode user).
# Verifies ~/.gitconfig has gpg.format=ssh and commit.gpgsign=true.
set -e

source dev-container-features-test-lib

# --- gh installed ---
check "gh on PATH" command -v gh
check "gh --version succeeds" gh --version

# --- .gitconfig written for vscode user ---
echo "=== /home/vscode/.gitconfig ==="
cat /home/vscode/.gitconfig 2> /dev/null || echo "(missing)"

check ".gitconfig exists for vscode user" test -f /home/vscode/.gitconfig
check "gpg.format is ssh" bash -c \
  '[ "$(git config --file /home/vscode/.gitconfig gpg.format 2>/dev/null)" = "ssh" ]'
check "commit.gpgsign is true" bash -c \
  '[ "$(git config --file /home/vscode/.gitconfig commit.gpgsign 2>/dev/null)" = "true" ]'
check ".gitconfig owned by vscode" bash -c \
  '[ "$(stat -c %U /home/vscode/.gitconfig 2>/dev/null)" = "vscode" ]'

reportResults
