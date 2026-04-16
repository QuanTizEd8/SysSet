#!/bin/bash
# method=source, prefix=/opt/git, symlink=true, running as non-root (vscode).
# Verifies git is installed at /opt/git/bin/git and a symlink is created at
# $HOME/.local/bin/git -> /opt/git/bin/git.
set -e

source dev-container-features-test-lib

# --- binary at custom prefix ---
check "git at /opt/git/bin/git" test -f /opt/git/bin/git
check "git binary is executable" test -x /opt/git/bin/git
check "git exec-path lives under /opt/git" bash -c '/opt/git/bin/git --exec-path | grep -Fq "/opt/git"'

# --- symlink $HOME/.local/bin/git → /opt/git/bin/git ---
check "\$HOME/.local/bin/git exists" test -e /home/vscode/.local/bin/git
check "\$HOME/.local/bin/git is a symlink" test -L /home/vscode/.local/bin/git
check "symlink target is /opt/git/bin/git" bash -c '[ "$(readlink /home/vscode/.local/bin/git)" = "/opt/git/bin/git" ]'

# --- no system-wide symlink created (non-root cannot write /usr/local/bin) ---
check "no symlink at /usr/local/bin/git" bash -c '! test -L /usr/local/bin/git'

reportResults
