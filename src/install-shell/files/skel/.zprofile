# ~/.zprofile: sourced by zsh for login shells, after ~/.zshenv and before
# ~/.zshrc.  Mirrors what ~/.bash_profile does for bash login shells.
#
# Delegates to ~/.bash_profile via 'emulate sh' so login-shell setup is
# defined once.  The $BASH guard in ~/.bash_profile ensures .bashrc is not
# sourced from this path.
[ -f "$HOME/.bash_profile" ] && emulate sh -c '. "$HOME/.bash_profile"'

# Add login-only zsh config below (ssh-agent, keychain, macOS GUI vars, etc.):
#
#   eval "$(ssh-agent -s)"
#   eval "$(keychain --eval id_ed25519)"
