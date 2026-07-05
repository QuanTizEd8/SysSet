# >>> setup-shell-sys-bashrc-guard >>>
case $- in
  *i*) ;;
    *) return;;
esac
# <<< setup-shell-sys-bashrc-guard <<<

# >>> setup-shell-sys-bashrc-shellrc >>>
. "/etc/shellrc"
# <<< setup-shell-sys-bashrc-shellrc <<<

# >>> setup-shell-sys-bashrc-ps1 >>>
PS1='\u@\h:\w\$ '
# <<< setup-shell-sys-bashrc-ps1 <<<

# >>> setup-shell-sys-bashrc-history >>>
HISTIGNORE="pwd:exit:clear"
HISTCONTROL=erasedups:ignoredups:ignorespace
HISTSIZE=1000
HISTFILESIZE=5000
HISTTIMEFORMAT='%F %T '
PROMPT_COMMAND="history -a; history -n"
shopt -s histappend
# <<< setup-shell-sys-bashrc-history <<<

# >>> setup-shell-sys-bashrc-shopt >>>
shopt -s checkwinsize
# <<< setup-shell-sys-bashrc-shopt <<<

# >>> setup-shell-sys-bashrc-completion >>>
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi
# <<< setup-shell-sys-bashrc-completion <<<

# >>> setup-shell-sys-bashrc-term-program >>>
_bashrc_dir="$(dirname "${BASH_SOURCE[0]}")"
[ -r "${_bashrc_dir}/bashrc_${TERM_PROGRAM}" ] && . "${_bashrc_dir}/bashrc_${TERM_PROGRAM}"
unset _bashrc_dir
# <<< setup-shell-sys-bashrc-term-program <<<

