# ~/.bash_profile: executed by bash for login shells.
#
# Bash does not source ~/.bashrc for login shells, so we do it here.
# This ensures login shells (SSH, console, su -l) get the same interactive
# config as non-login shells (new terminal tabs, etc.).
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
