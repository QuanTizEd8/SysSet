#!/bin/bash
# shell_activations="bash zsh": conda init blocks are written to both the
# system-wide bash rc file and the system-wide zsh rc file (running as root).
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- bash rc file was written ---
check "/etc/bash.bashrc exists" test -f /etc/bash.bashrc
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"

# --- zsh rc file was written ---
# shell__detect_zshdir returns /etc/zsh on Debian/Ubuntu; the target is /etc/zsh/zshrc.
check "/etc/zsh/zshrc exists" test -f /etc/zsh/zshrc
echo "=== /etc/zsh/zshrc ==="
cat /etc/zsh/zshrc 2> /dev/null || echo "(missing)"

# --- our idempotency block markers are present in /etc/bash.bashrc ---
check "miniforge begin marker in /etc/bash.bashrc" grep -Fq "# >>> conda init (install-miniforge) >>>" /etc/bash.bashrc
check "conda initialize begin marker in /etc/bash.bashrc" grep -Fq "# >>> conda initialize >>>" /etc/bash.bashrc

# --- our idempotency block markers are present in /etc/zsh/zshrc ---
check "miniforge begin marker in /etc/zsh/zshrc" grep -Fq "# >>> conda init (install-miniforge) >>>" /etc/zsh/zshrc
check "conda initialize begin marker in /etc/zsh/zshrc" grep -Fq "# >>> conda initialize >>>" /etc/zsh/zshrc

# --- neither file has duplicated markers ---
check "no dup miniforge marker in /etc/bash.bashrc" bash -c '[ "$(grep -Fc "# >>> conda init (install-miniforge) >>>" /etc/bash.bashrc)" -eq 1 ]'
check "no dup miniforge marker in /etc/zsh/zshrc" bash -c '[ "$(grep -Fc "# >>> conda init (install-miniforge) >>>" /etc/zsh/zshrc)" -eq 1 ]'

reportResults
