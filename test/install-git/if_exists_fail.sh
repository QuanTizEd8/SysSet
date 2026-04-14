#!/bin/bash
# if_exists=fail with no pre-existing git should behave like a normal install.
# The actual failure path is covered in fail_scenarios.sh with a preinstall
# setup command.
set -e

source dev-container-features-test-lib

# --- fresh install succeeded despite if_exists=fail ---
check "git on PATH" command -v git
check "git --version succeeds" git --version
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is main" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "main" ]'

reportResults
