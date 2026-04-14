#!/bin/bash
# method=source, version=stable: full source build from kernel.org tarball.
# Verifies source-specific artifacts that package installs do not create.
set -e

source dev-container-features-test-lib

# --- binary at default prefix ---
check "git at /usr/local/bin/git" test -f /usr/local/bin/git
check "git binary is executable" test -x /usr/local/bin/git
check "command -v resolves to /usr/local/bin/git" bash -c '[ "$(command -v git)" = "/usr/local/bin/git" ]'
echo "=== git --version ==="
/usr/local/bin/git --version 2>&1 || echo "(failed)"
check "git --version succeeds" /usr/local/bin/git --version
check "git version is at least 2" bash -c '[ "$(/usr/local/bin/git --version | awk "{print \$3}" | cut -d. -f1)" -ge 2 ]'

# --- no apt source list created (source build, no PPA) ---
check "no PPA sources.list entry" bash -c '! test -f /etc/apt/sources.list.d/git-core-ppa.list'

# --- system gitconfig (default_branch=main default) ---
check "/etc/gitconfig created" test -f /etc/gitconfig
check "init.defaultBranch is main" bash -c '[ "$(git config --file /etc/gitconfig init.defaultBranch 2>/dev/null)" = "main" ]'

# --- PATH export (export_path=auto default) ---
echo "=== /etc/profile.d/install-git.sh ==="
cat /etc/profile.d/install-git.sh 2> /dev/null || echo "(missing)"
check "profile.d script written" test -f /etc/profile.d/install-git.sh
check "profile.d has PATH block" grep -Fq 'git PATH (install-git)' /etc/profile.d/install-git.sh
check "profile.d exports /usr/local/bin" grep -Fq 'export PATH="/usr/local/bin:${PATH}"' /etc/profile.d/install-git.sh
check "bashrc has PATH marker" grep -Fq 'git PATH (install-git)' /etc/bash.bashrc
check "zshenv has PATH marker" grep -Fq 'git PATH (install-git)' /etc/zsh/zshenv

# --- shell completions (install_completions=true default) ---
check "bash completion installed" test -f /etc/bash_completion.d/git
check "zsh completion installed in detected zshdir" test -f /etc/zsh/completions/_git

reportResults
