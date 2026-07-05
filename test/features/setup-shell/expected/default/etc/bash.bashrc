# System-wide .bashrc file for interactive bash(1) shells.

# To enable the settings / commands in this file for login shells as well,
# this file has to be sourced in /etc/profile.

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, overwrite the one in /etc/profile)
# but only if not SUDOing and have SUDO_PS1 set; then assume smart user.
if ! [ -n "${SUDO_USER}" -a -n "${SUDO_PS1}" ]; then
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi

# Commented out, don't overwrite xterm -T "title" -n "icontitle" by default.
# If this is an xterm set the title to user@host:dir
#case "$TERM" in
#xterm*|rxvt*)
#    PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD}\007"'
#    ;;
#*)
#    ;;
#esac

# enable bash completion in interactive shells
#if ! shopt -oq posix; then
#  if [ -f /usr/share/bash-completion/bash_completion ]; then
#    . /usr/share/bash-completion/bash_completion
#  elif [ -f /etc/bash_completion ]; then
#    . /etc/bash_completion
#  fi
#fi

# if the command-not-found package is installed, use it
if [ -x /usr/lib/command-not-found -o -x /usr/share/command-not-found/command-not-found ]; then
	function command_not_found_handle {
	        # check because c-n-f could've been removed in the meantime
                if [ -x /usr/lib/command-not-found ]; then
		   /usr/lib/command-not-found -- "$1"
                   return $?
                elif [ -x /usr/share/command-not-found/command-not-found ]; then
		   /usr/share/command-not-found/command-not-found -- "$1"
                   return $?
		else
		   printf "%s: command not found\n" "$1" >&2
		   return 127
		fi
	}
fi

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

