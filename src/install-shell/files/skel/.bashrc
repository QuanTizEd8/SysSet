# ~/.bashrc: user-specific bash interactive shell configuration.

# If not running interactively, don't do anything.
case $- in
    *i*) ;;
      *) return;;
esac

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
#       eval "$(starship init bash)"     # Starship prompt
#       eval "$(fnm env)"                # fnm (Node version manager)
#       eval "$(pyenv init -)"           # pyenv
#   - History tuning overrides:
#       HISTSIZE=50000
