# shellcheck shell=bash

# install-bash-completion installs the bash-completion v2 package via the OS
# package manager (the framework's package method handles install, update, and
# removal). Activation on Linux needs no action here: the package's
# /etc/profile.d entry point covers login shells, and setup-shell's system
# bashrc completion block covers interactive non-login shells. On Homebrew,
# /etc/profile.d is not sourced, so a managed block sourcing the Homebrew entry
# point is written to each configured user's ~/.bashrc.

_IBC_MARKER="install-bash-completion"

_ibc_brew_entrypoint() {
  # Print the Homebrew profile.d entry-point path when it exists; fail otherwise.
  command -v brew > /dev/null 2>&1 || return 1
  local _ep
  _ep="$(brew --prefix)/etc/profile.d/bash_completion.sh"
  [ -f "$_ep" ] || return 1
  printf '%s' "$_ep"
}

# shellcheck disable=SC2329,SC2317
__detect_existing_path_post() {
  # No binary to probe: signal a prior install via the main completion file.
  # Method derivation (ospkg__is_managed on this path) then resolves `package`.
  local _f
  for _f in \
    /usr/share/bash-completion/bash_completion \
    /etc/bash_completion; do
    if [ -f "$_f" ]; then
      _FEAT_EXISTING=true
      _FEAT_EXISTING_PATH="$_f"
      return 0
    fi
  done
  local _ep
  if _ep="$(_ibc_brew_entrypoint)"; then
    _FEAT_EXISTING=true
    _FEAT_EXISTING_PATH="$_ep"
  fi
  return 0
}

# shellcheck disable=SC2329,SC2317
__configure_user() {
  # Homebrew only: wire the entry point into the user's ~/.bashrc. On Linux the
  # package is auto-activated (profile.d + setup-shell's completion block).
  local _username="$1"
  local _ep
  _ep="$(_ibc_brew_entrypoint)" || return 0
  local _home
  _home="$(users__resolve_home "$_username")"
  shell__write_block --file "${_home}/.bashrc" --marker "${_IBC_MARKER}" \
    --content "[ -r \"${_ep}\" ] && . \"${_ep}\""
  logging__success "  bash-completion Homebrew hook → ${_home}/.bashrc"
}

# shellcheck disable=SC2329,SC2317
__uninstall_finish_post() {
  # Strip the per-user Homebrew hook blocks (no-op where none were written).
  local -a _users=()
  mapfile -t _users < <(users__resolve_list)
  local _user
  for _user in "${_users[@]+"${_users[@]}"}"; do
    users__uid_of_user "${_user}" > /dev/null 2>&1 || continue
    local _home
    _home="$(users__resolve_home "${_user}")"
    [ -f "${_home}/.bashrc" ] || continue
    shell__sync_block --files "${_home}/.bashrc" --marker "${_IBC_MARKER}"
  done
}
