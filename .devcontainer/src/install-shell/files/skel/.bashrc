# ~/.bashrc: user-specific bash interactive shell configuration.

# If not running interactively, don't do anything.
case $- in
    *i*) ;;
      *) return;;
esac

# --- Framework / prompt configuration ---------------------------------- #
# Shell theme, framework (Oh My Bash), and prompt settings live in a       #
# dedicated file so they can be managed independently of this file.        #
# The install-shell feature writes ~/.config/bash/bashtheme at build time. #
_BASH_THEME="${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashtheme"
[ -f "$_BASH_THEME" ] && . "$_BASH_THEME"
unset _BASH_THEME


# Load shared user interactive config (POSIX aliases, functions, cross-shell
# tool initialisers).  Sourced here and in ~/.zshrc for both shells.
[ -f "$HOME/.shellrc" ] && . "$HOME/.shellrc"

# The system config in /etc/bash/bashrc has already run by this point and
# provides: shared aliases, dircolors, history settings, completions, etc.
#
# Add your personal overrides and extensions below.
#
# Common things to put here:
#   - Additional PATH entries:
#       export PATH="$HOME/.local/bin:$PATH"
#   - Personal aliases:
#       alias gs='git status'
#   - Tool initialisers (run `tool --help` or docs for the exact snippet):
#       eval "$(fnm env)"                # fnm (Node version manager)
#       eval "$(pyenv init -)"           # pyenv
#       # Note: Starship and Oh My Bash are configured in ~/.config/bash/bashtheme
#   - History tuning overrides:
#       HISTSIZE=50000
