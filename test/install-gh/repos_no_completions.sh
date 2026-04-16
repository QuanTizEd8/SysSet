#!/bin/bash
# method=repos (default), shell_completions="" (no completions) on Ubuntu:
# gh is installed via the official apt repo but completion files must NOT be written.
set -e

source dev-container-features-test-lib

# --- binary present and callable ---
check "gh binary installed" command -v gh
check "gh --version succeeds" gh --version

# --- NO bash completion file ---
echo "=== /etc/bash_completion.d/gh (should be absent) ==="
ls -la /etc/bash_completion.d/gh 2> /dev/null || echo "(correctly absent)"
check "no bash completion file" bash -c '! test -f /etc/bash_completion.d/gh'

# --- NO zsh completion file written by this feature ---
# The feature (as root, debian/ubuntu) writes zsh completions to /etc/zsh/completions/_gh.
# The gh deb package itself may install _gh elsewhere (e.g. /usr/share/zsh/), which is
# not our concern here — only the path the feature would write is checked.
echo "=== feature zsh completion path (should be absent) ==="
ls -la /etc/zsh/completions/_gh 2> /dev/null || echo "(correctly absent)"
check "no feature-written zsh completion" bash -c '! test -f /etc/zsh/completions/_gh'

reportResults
