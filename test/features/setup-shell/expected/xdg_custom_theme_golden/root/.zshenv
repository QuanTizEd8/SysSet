# >>> setup-shell-user-zshenv-shellenv >>>
[ -f "/root/.shellenv" ] && emulate sh -c ". \"/root/.shellenv\""
# <<< setup-shell-user-zshenv-shellenv <<<

# >>> setup-shell-zdotdir >>>
export ZDOTDIR="/root/.local/config/zsh"
# <<< setup-shell-zdotdir <<<

