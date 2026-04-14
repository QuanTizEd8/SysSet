#!/bin/bash
# Per-user gitconfig: users=_REMOTE_USER with user_name, user_email, and a raw
# user_gitconfig block. Verifies both parsed keys and verbatim content.
set -e

source dev-container-features-test-lib

# --- binary ---
check "git on PATH" command -v git
check "git --version succeeds" git --version

# --- per-user gitconfig ---
echo "=== /home/vscode/.gitconfig ==="
cat /home/vscode/.gitconfig 2> /dev/null || echo "(missing)"

check "vscode .gitconfig exists" test -f /home/vscode/.gitconfig
check "user.name is Dev User" bash -c '[ "$(git config --file /home/vscode/.gitconfig user.name 2>/dev/null)" = "Dev User" ]'
check "user.email is dev@example.com" bash -c '[ "$(git config --file /home/vscode/.gitconfig user.email 2>/dev/null)" = "dev@example.com" ]'
check "pull.rebase is false" bash -c '[ "$(git config --file /home/vscode/.gitconfig pull.rebase 2>/dev/null)" = "false" ]'
check "raw user_gitconfig block is present" grep -Fq '[pull]' /home/vscode/.gitconfig
check ".gitconfig owned by vscode" bash -c '[ "$(stat -c %U /home/vscode/.gitconfig 2>/dev/null)" = "vscode" ]'

reportResults
