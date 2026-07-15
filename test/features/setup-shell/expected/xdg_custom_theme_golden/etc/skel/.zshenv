# >>> setup-shell-user-zshenv-shellenv >>>
[ -f "$HOME/.shellenv" ] && emulate sh -c ". \"$HOME/.shellenv\""
# <<< setup-shell-user-zshenv-shellenv <<<

# >>> setup-shell-zdotdir >>>
export ZDOTDIR="${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
# <<< setup-shell-zdotdir <<<

