# ~/.zshrc: user-specific zsh interactive shell configuration.

# If not running interactively, don't do anything.
case $- in
    *i*) ;;
      *) return;;
esac

# --- Framework / prompt configuration ---------------------------------- #
# Shell theme, framework (Oh My Zsh), and prompt settings live in a        #
# dedicated file so they can be managed independently of this file.        #
# The install-shell feature writes ~/.config/zsh/zshtheme at build time.   #
[ -f "${ZDOTDIR}/zshtheme" ] && source "${ZDOTDIR}/zshtheme"


# --- Shared user interactive config ------------------------------------- #
# Source ~/.shellrc for POSIX-compatible aliases and functions shared       #
# with bash.  Sourced after the framework block so user config can         #
# override framework defaults.                                             #
[ -f "$HOME/.shellrc" ] && . "$HOME/.shellrc"


# The system config in /etc/zsh/zshrc has already run by this point and
# provides: key bindings, completion styles, dircolors, lesspipe, etc.
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
#       # Note: Starship and Oh My Zsh are configured in ${ZDOTDIR}/zshtheme
#   - History tuning overrides:
#       HISTSIZE=50000
