#!/bin/bash
# method=source, version=stable, prefix=/opt/git: custom install prefix.
# Verifies git is installed at /opt/git/bin/git and a symlink
# /usr/local/bin/git -> /opt/git/bin/git is created (symlink=true default).
set -e

source dev-container-features-test-lib

# --- binary at custom prefix ---
check "git at /opt/git/bin/git" test -f /opt/git/bin/git
check "git binary is executable" test -x /opt/git/bin/git
check "git exec-path lives under /opt/git" bash -c '/opt/git/bin/git --exec-path | grep -Fq "/opt/git"'
echo "=== /opt/git/bin/git --version ==="
/opt/git/bin/git --version 2>&1 || echo "(failed)"
check "git --version succeeds" /opt/git/bin/git --version

# --- symlink /usr/local/bin/git → /opt/git/bin/git ---
check "/usr/local/bin/git exists" test -e /usr/local/bin/git
check "/usr/local/bin/git is a symlink" test -L /usr/local/bin/git
check "symlink target is /opt/git/bin/git" bash -c '[ "$(readlink /usr/local/bin/git)" = "/opt/git/bin/git" ]'
check "git canonically resolves to /opt/git/bin/git" bash -c '[ "$(readlink -f "$(command -v git)")" = "/opt/git/bin/git" ]'

# --- PATH export written for non-standard prefix ---
echo "=== /etc/profile.d/install-git.sh ==="
cat /etc/profile.d/install-git.sh 2> /dev/null || echo "(missing)"
check "profile.d script written" test -f /etc/profile.d/install-git.sh
check "profile.d exports /opt/git/bin" grep -Fq 'export PATH="/opt/git/bin:${PATH}"' /etc/profile.d/install-git.sh
check "profile.d exports /opt/git/share/man" grep -Fq 'export MANPATH="/opt/git/share/man:${MANPATH}"' /etc/profile.d/install-git.sh

reportResults
