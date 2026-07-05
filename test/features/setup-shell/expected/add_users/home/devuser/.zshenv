# >>> setup-shell-user-zshenv-shellenv >>>
[ -f "/home/devuser/.shellenv" ] && emulate sh -c ". \"/home/devuser/.shellenv\""
# <<< setup-shell-user-zshenv-shellenv <<<

# >>> setup-shell-zdotdir >>>
export ZDOTDIR="/home/devuser/.config/zsh"
# <<< setup-shell-zdotdir <<<

