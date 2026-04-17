#!/bin/bash
# sign_commits=gpg + add_remote_user=true (vscode user).
# Verifies ~/.gitconfig has commit.gpgsign=true and does NOT have gpg.format set
# (GPG is the git default; unsetting gpg.format is correct to avoid SSH override).
set -e

source dev-container-features-test-lib

# --- gh installed ---
check "gh on PATH" command -v gh
check "gh --version succeeds" gh --version

# --- .gitconfig written for vscode user ---
echo "=== /home/vscode/.gitconfig ==="
cat /home/vscode/.gitconfig 2> /dev/null || echo "(missing)"

check ".gitconfig exists for vscode user" test -f /home/vscode/.gitconfig
check "commit.gpgsign is true" bash -c \
  '[ "$(git config --file /home/vscode/.gitconfig commit.gpgsign 2>/dev/null)" = "true" ]'
# gpg.format must NOT be present (or must be empty) — GPG is the git default
check "gpg.format is not set to ssh" bash -c \
  '[ "$(git config --file /home/vscode/.gitconfig gpg.format 2>/dev/null)" != "ssh" ]'
check ".gitconfig owned by vscode" bash -c \
  '[ "$(stat -c %U /home/vscode/.gitconfig 2>/dev/null)" = "vscode" ]'

reportResults
