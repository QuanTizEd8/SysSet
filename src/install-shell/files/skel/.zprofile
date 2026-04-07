# ~/.zprofile: sourced by zsh for login shells, after ~/.zshenv and before
# ~/.zshrc.  Equivalent to ~/.bash_profile for zsh.
#
# Unlike bash, zsh sources ~/.zshrc even for interactive login shells, so
# you rarely need this file for interactive config. It is mainly useful for:
#
#   - Starting agents that should run once per login session:
#       eval "$(ssh-agent -s)"
#       eval "$(keychain --eval id_ed25519)"
#
#   - macOS GUI environment variables (e.g. launched via launchd):
#       export BROWSER="open"
#
#   - Login-only PATH setup that must not affect scripts (e.g. GUI apps):
#       export PATH="/Applications/Foo.app/Contents/MacOS:$PATH"
