# ~/.bashrc: user-specific bash interactive shell configuration.

# If not running interactively, don't do anything.
case $- in
    *i*) ;;
      *) return;;
esac

# --- Framework configuration -------------------------------------------- #
# The install-shell installer injects an Oh My Bash configuration block    #
# between the BEGIN/END markers below.  If no framework is installed, the  #
# block is empty and bash runs with plain defaults.                        #
#                                                                          #
# To customise: edit the block contents or add your own settings after     #
# the END marker.  Re-running the installer with user_config_mode=augment  #
# will refresh only the marked block without touching your changes.        #

# BEGIN install-shell-ohmybash
# END install-shell-ohmybash


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
#       eval "$(starship init bash)"     # Starship prompt
#       eval "$(fnm env)"                # fnm (Node version manager)
#       eval "$(pyenv init -)"           # pyenv
#   - History tuning overrides:
#       HISTSIZE=50000
