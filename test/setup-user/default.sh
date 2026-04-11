#!/bin/bash
# Default options: username=vscode, user_id=1000, group_id=1000, sudo_access=true,
# user_shell=/bin/bash.  Verifies the full happy-path of user creation.
set -e

source dev-container-features-test-lib

# --- user account ---
check "vscode user exists" bash -c 'id vscode > /dev/null 2>&1'
check "vscode has UID 1000" bash -c '[ "$(id -u vscode)" = "1000" ]'
check "vscode has GID 1000" bash -c '[ "$(id -g vscode)" = "1000" ]'
check "vscode primary group is vscode" bash -c '[ "$(id -gn vscode)" = "vscode" ]'

# --- home directory ---
check "home directory /home/vscode exists" test -d /home/vscode
check "home directory owned by vscode" bash -c '[ "$(stat -c "%U" /home/vscode)" = "vscode" ]'
check "home directory group-owned by vscode" bash -c '[ "$(stat -c "%G" /home/vscode)" = "vscode" ]'

# --- login shell ---
check "login shell is /bin/bash" bash -c '[ "$(awk -F: '\''$1=="vscode"{print $7}'\'' /etc/passwd)" = "/bin/bash" ]'

# --- sudo ---
check "sudo binary is installed" bash -c 'command -v sudo'
check "sudoers file exists" test -f /etc/sudoers.d/vscode
check "sudoers file has correct perms" bash -c '[ "$(stat -c "%a" /etc/sudoers.d/vscode)" = "440" ]'
check "sudoers grants NOPASSWD:ALL" grep -q "vscode ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/vscode

reportResults
