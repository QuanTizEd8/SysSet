# --- Powerlevel10k instant prompt --------------------------------------- #
# Must be sourced at the very top of zshrc, before any output or slow     #
# initialisation, to enable the instant-prompt feature.  Skipped if the   #
# cache file does not yet exist (first login before p10k configure runs). #
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi