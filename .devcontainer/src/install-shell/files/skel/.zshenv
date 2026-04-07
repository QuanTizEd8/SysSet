# ~/.zshenv: sourced for EVERY zsh invocation — interactive, non-interactive,
# login, scripts, cron jobs, and remote commands over SSH.
#
# Delegates to ~/.shellenv (POSIX sh) for environment variables and PATH
# additions shared with bash.  The sentinel in ~/.shellenv prevents
# double-sourcing when zprofile also sources bash_profile → shellenv.
#
# Do NOT put interactive-only config here (aliases, prompt, key bindings).
# Those belong in ~/.zshrc.  Output here WILL break scripts and scp/rsync.
[ -f "$HOME/.shellenv" ] && emulate sh -c '. "$HOME/.shellenv"'


# Path to the directory where
# Zsh configuration files (dotfiles)
# are located (default: $HOME).
# - https://www.reddit.com/r/zsh/comments/iq89wr/comment/g4soljs/
ZDOTDIR="${XDG_CONFIG_HOME}/zsh"
