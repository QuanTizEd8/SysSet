# >>> setup-shell-user-bashrc-interactive-guard >>>
case $- in
  *i*) ;;
    *) return;;
esac
# <<< setup-shell-user-bashrc-interactive-guard <<<

# >>> setup-shell-user-bashrc-bashtheme >>>
_BASH_THEME="${XDG_CONFIG_HOME:-${HOME}/.config}/bash/bashtheme"
[ -f "$_BASH_THEME" ] && . "$_BASH_THEME"
unset _BASH_THEME
# <<< setup-shell-user-bashrc-bashtheme <<<

# >>> setup-shell-user-bashrc-shellrc >>>
[ -f "$HOME/.shellrc" ] && . "$HOME/.shellrc"
# <<< setup-shell-user-bashrc-shellrc <<<

