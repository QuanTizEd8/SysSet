#!/bin/bash
# if_exists=reinstall with preinstalled package git, switching to source.
# Verifies the package install is replaced by a source build under /opt/git.
set -e

source dev-container-features-test-lib

check "source-installed git exists" test -x /opt/git/bin/git
check "git exec-path moved under /opt/git" bash -c '/opt/git/bin/git --exec-path | grep -Fq "/opt/git"'
check "symlink created for source install" bash -c '[ "$(readlink /usr/local/bin/git)" = "/opt/git/bin/git" ]'
check "command -v resolves to /usr/local/bin/git" bash -c '[ "$(command -v git)" = "/usr/local/bin/git" ]'
check "/etc/gitconfig created after reinstall" test -f /etc/gitconfig
check "init.defaultBranch is trunk" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "trunk" ]'

reportResults
