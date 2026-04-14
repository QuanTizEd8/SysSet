#!/bin/bash
# add_user_config="testuser" + setup_git=true + all other add_*_user_config=false.
# Verifies that the feature targets exactly the user named in add_user_config,
# writing the gh credential helper to /home/testuser/.gitconfig.
set -e

source dev-container-features-test-lib

# --- gh installed ---
check "gh on PATH" command -v gh
check "gh --version succeeds" gh --version

# --- .gitconfig written for testuser ---
echo "=== /home/testuser/.gitconfig ==="
cat /home/testuser/.gitconfig 2> /dev/null || echo "(missing)"

check ".gitconfig exists for testuser" test -f /home/testuser/.gitconfig
check ".gitconfig contains gh auth git-credential helper" bash -c \
  'grep -q "gh auth git-credential" /home/testuser/.gitconfig 2>/dev/null'
check ".gitconfig has github.com credential section" bash -c \
  'git config --file /home/testuser/.gitconfig --get-all \
     credential."https://github.com".helper 2>/dev/null | grep -q "gh auth git-credential"'
check ".gitconfig owned by testuser" bash -c \
  '[ "$(stat -c %U /home/testuser/.gitconfig 2>/dev/null)" = "testuser" ]'

reportResults
