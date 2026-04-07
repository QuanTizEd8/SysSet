# ~/.zshrc: user-specific zsh interactive shell configuration.

# If not running interactively, don't do anything.
case $- in
    *i*) ;;
      *) return;;
esac

# --- Framework configuration -------------------------------------------- #
# The install-shell installer injects an Oh My Zsh configuration block     #
# between the BEGIN/END markers below.  If no framework is installed, the  #
# block is empty and zsh runs with plain defaults.                         #
#                                                                          #
# To customise: edit the block contents or add your own settings after     #
# the END marker.  Re-running the installer with user_config_mode=augment  #
# will refresh only the marked block without touching your changes.        #

# BEGIN install-shell-ohmyzsh
# END install-shell-ohmyzsh


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
#       eval "$(starship init zsh)"      # Starship prompt
#       eval "$(fnm env)"                # fnm (Node version manager)
#       eval "$(pyenv init -)"           # pyenv
#   - History tuning overrides:
#       HISTSIZE=50000
