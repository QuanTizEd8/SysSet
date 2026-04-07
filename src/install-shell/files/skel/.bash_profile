# ~/.bash_profile: executed by bash (and zsh via ~/.zprofile) for login shells.
#
# Sources ~/.shellenv for environment variables, then ~/.bashrc for interactive
# bash config.  The ~/.bashrc source is guarded by $BASH so that when zsh
# sources this file via 'emulate sh', bash-specific files are not loaded.
[ -f "$HOME/.shellenv" ] && . "$HOME/.shellenv"

if [ "${BASH-}" ] && [ "$BASH" != "/bin/sh" ]; then
    [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
fi
