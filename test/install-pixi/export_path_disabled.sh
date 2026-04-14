#!/bin/bash
# bin_dir=/opt/pixi-bin, export_path="" (disabled), symlink=false:
# Verifies pixi is installed but no PATH export block is written anywhere.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "pixi binary installed at /opt/pixi-bin/pixi" test -f /opt/pixi-bin/pixi
check "pixi binary is executable" test -x /opt/pixi-bin/pixi
check "/opt/pixi-bin/pixi --version succeeds" /opt/pixi-bin/pixi --version

# --- no PATH blocks written at all ---
check "no profile.d pixi_bin_path.sh written" bash -c '! test -f /etc/profile.d/pixi_bin_path.sh'
check "no pixi PATH marker in bash.bashrc" bash -c '! grep -Fq "pixi PATH (install-pixi)" /etc/bash.bashrc 2>/dev/null'
check "no pixi PATH marker in zshenv" bash -c '! grep -Fq "pixi PATH (install-pixi)" /etc/zsh/zshenv 2>/dev/null'

reportResults
