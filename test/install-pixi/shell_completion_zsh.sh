#!/bin/bash
# shell_completion=true, shell_type=zsh (root):
# Verifies pixi shell completion eval block is written to the system-wide zshenv.
# Checks both /etc/zsh/zshenv (Debian/Ubuntu default) and /etc/zshenv (RHEL/Alpine fallback).
set -e

source dev-container-features-test-lib

# --- pixi installed ---
check "pixi binary installed" test -f /usr/local/bin/pixi
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- zsh completion block written to one of the system-wide zshenv paths ---
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"
echo "=== /etc/zshenv ==="
cat /etc/zshenv 2> /dev/null || echo "(missing)"
check "completion marker in a system zshenv" bash -c \
  'grep -Fq "pixi completion (install-pixi)" /etc/zsh/zshenv 2>/dev/null \
  || grep -Fq "pixi completion (install-pixi)" /etc/zshenv 2>/dev/null'
check "completion eval in a system zshenv" bash -c \
  'grep -Fq "pixi completion --shell zsh" /etc/zsh/zshenv 2>/dev/null \
  || grep -Fq "pixi completion --shell zsh" /etc/zshenv 2>/dev/null'

reportResults
