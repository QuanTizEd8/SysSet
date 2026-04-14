#!/bin/bash
# System gitconfig with a custom default branch, multiple safe.directory
# entries, and a multi-line raw block.
set -e

source dev-container-features-test-lib

# --- binary ---
check "git on PATH" command -v git
check "git --version succeeds" git --version

# --- /etc/gitconfig content ---
echo "=== /etc/gitconfig ==="
cat /etc/gitconfig || echo "(missing)"

check "/etc/gitconfig exists" test -f /etc/gitconfig
check "init.defaultBranch is trunk" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "trunk" ]'
check "safe.directory has three entries" bash -c '[ "$(git config --file /etc/gitconfig --get-all safe.directory 2>/dev/null | wc -l)" -eq 3 ]'
check "safe.directory keeps wildcard" bash -c 'git config --file /etc/gitconfig --get-all safe.directory 2>/dev/null | grep -Fxq "*"'
check "safe.directory keeps /workspaces/sysset" bash -c 'git config --file /etc/gitconfig --get-all safe.directory 2>/dev/null | grep -Fxq "/workspaces/sysset"'
check "safe.directory keeps /tmp/repo" bash -c 'git config --file /etc/gitconfig --get-all safe.directory 2>/dev/null | grep -Fxq "/tmp/repo"'
check "push.default is simple" bash -c '[ "$(git config --file /etc/gitconfig push.default 2>/dev/null)" = "simple" ]'
check "fetch.prune is true" bash -c '[ "$(git config --file /etc/gitconfig fetch.prune 2>/dev/null)" = "true" ]'

reportResults
