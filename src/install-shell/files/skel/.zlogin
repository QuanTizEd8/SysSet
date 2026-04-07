# ~/.zlogin: sourced by zsh for login shells, after ~/.zshrc.
#
# Runs last in the login shell startup sequence, making it the right place
# for things that should appear after the prompt is fully initialised:
#
#   - Login announcements and MOTD-style output:
#       echo "Welcome, $USER. Today is $(date '+%A %d %B %Y')."
#       fortune
#
#   - Session-level checks (disk space warnings, certificate expiry, etc.)
#
# Most users will leave this file empty. Prefer ~/.zshrc for interactive
# config and ~/.zprofile for login-only environment setup.
