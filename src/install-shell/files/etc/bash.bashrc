# System-wide .bashrc file for interactive bash(1) shells.
# Sourced for all interactive bash sessions (non-login and login, via /etc/profile).

# If not running interactively, don't do anything.
case $- in
  *i*) ;;
    *) return;;
esac

# Load shared interactive config (aliases, functions) and bash prompt/theme.
. "/etc/global_shellrc"
. "/etc/bash/bash_theme"

# --- History ---
# Ignore simple commands and deduplicate: erase all earlier occurrences of a
# command when a new one is added, also skip consecutive duplicates and lines
# starting with space.
HISTIGNORE="pwd:exit:clear"
HISTCONTROL=erasedups:ignoredups:ignorespace
HISTSIZE=1000
HISTFILESIZE=5000
# Prefix each history entry with a timestamp for audit and context.
HISTTIMEFORMAT='%F %T '
# After each command: append to the history file (history -a) then reload it
# (history -n), keeping history in sync across concurrent sessions.
PROMPT_COMMAND="history -a; history -n"
# Append to the history file on exit instead of overwriting it.
shopt -s histappend

# --- Shell Options ---
# Update LINES and COLUMNS after each command to reflect terminal resize.
shopt -s checkwinsize

# --- Bash Completion ---
# Load programmable tab-completion (skip in POSIX compatibility mode).
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# --- sudo hint ---
# On first login for users in the admin/sudo group, print a one-time reminder
# about how to use sudo. Silenced by ~/.hushlogin or after first successful sudo.
if [ ! -e "$HOME/.sudo_as_admin_successful" ] && [ ! -e "$HOME/.hushlogin" ] && command -v sudo >/dev/null 2>&1; then
    case " $(groups) " in
        *\ admin\ *|*\ sudo\ *)
            printf '%s\n\n' \
                'To run a command as administrator (user "root"), use "sudo <command>".' \
                'See "man sudo_root" for details.'
            ;;
    esac
fi

# --- command-not-found handler ---
# When an unknown command is typed, suggest the package that provides it.
if [ -x /usr/lib/command-not-found -o -x /usr/share/command-not-found/command-not-found ]; then
    function command_not_found_handle {
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

# --- less ---
# Enable lesspipe so that less can display non-text files (archives, images, etc.)
# by invoking the appropriate preprocessor.
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# --- Colors ---
# Colorize GCC compiler diagnostics (errors, warnings, notes).
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# --- Tool completions ---
# Register tab-completion for pixi if it is installed.
command -v pixi >/dev/null 2>&1 && eval "$(pixi completion -s bash)"
