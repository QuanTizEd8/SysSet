#!/bin/bash
# method=source, version=2.47.2: pinned build from kernel.org tarball.
# Verifies exactly version 2.47.2 is installed.
# Update the version string and scenarios.json when 2.47.2 is retired.
set -e

source dev-container-features-test-lib

# --- binary at default prefix ---
check "git at /usr/local/bin/git" test -f /usr/local/bin/git
check "git binary is executable" test -x /usr/local/bin/git

echo "=== git --version ==="
/usr/local/bin/git --version 2>&1 || echo "(failed)"
check "git --version succeeds" /usr/local/bin/git --version

# --- exact version 2.47.2 ---
check "git version is 2.47.2" bash -c '[ "$(/usr/local/bin/git --version | sed "s/git version //")" = "2.47.2" ]'

# --- source cleanup defaults ---
check "default installer_dir was cleaned" bash -c '! test -e /tmp/git-build'

# --- system gitconfig ---
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is main" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "main" ]'

reportResults
