#!/bin/bash
# shell_completions=bash (root):
# Verifies pixi shell completion eval block is written to the system-wide bashrc.
# Checks /etc/bash.bashrc (Debian/Ubuntu), /etc/bashrc (RHEL), /etc/bash/bashrc (Alpine).
set -e

source dev-container-features-test-lib

# --- pixi installed ---
check "pixi binary installed" test -f /usr/local/bin/pixi
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- bash completion block written to one of the system-wide bashrc paths ---
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/bashrc ==="
cat /etc/bashrc 2> /dev/null || echo "(missing)"
check "completion marker in a system bashrc" bash -c \
  'grep -Fq "pixi completion (install-pixi)" /etc/bash.bashrc 2>/dev/null \
  || grep -Fq "pixi completion (install-pixi)" /etc/bashrc 2>/dev/null \
  || grep -Fq "pixi completion (install-pixi)" /etc/bash/bashrc 2>/dev/null'
check "completion eval in a system bashrc" bash -c \
  'grep -Fq "pixi completion --shell bash" /etc/bash.bashrc 2>/dev/null \
  || grep -Fq "pixi completion --shell bash" /etc/bashrc 2>/dev/null \
  || grep -Fq "pixi completion --shell bash" /etc/bash/bashrc 2>/dev/null'

reportResults
