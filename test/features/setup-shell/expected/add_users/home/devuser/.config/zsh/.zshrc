# >>> setup-shell-user-zshrc-guard >>>
case $- in
  *i*) ;;
    *) return;;
esac
# <<< setup-shell-user-zshrc-guard <<<

# >>> setup-shell-user-zshrc-zshtheme >>>
[ -f "${ZDOTDIR}/zshtheme" ] && source "${ZDOTDIR}/zshtheme"
# <<< setup-shell-user-zshrc-zshtheme <<<

# >>> setup-shell-user-zshrc-shellrc >>>
. "/home/devuser/.shellrc"
# <<< setup-shell-user-zshrc-shellrc <<<

