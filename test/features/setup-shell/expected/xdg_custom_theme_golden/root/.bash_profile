# >>> setup-shell-user-bashprofile-shellenv >>>
. "/root/.shellenv"
# <<< setup-shell-user-bashprofile-shellenv <<<

# >>> setup-shell-user-bashprofile-bashrc >>>
if [ "${BASH-}" ] && [ "$BASH" != "/bin/sh" ]; then
    [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
fi
# <<< setup-shell-user-bashprofile-bashrc <<<

