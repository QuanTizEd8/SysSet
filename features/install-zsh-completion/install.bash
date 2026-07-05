# shellcheck shell=bash

# install-zsh-completion shallow-clones the zsh-completions project and prepends
# its src/ directory to the zsh `fpath` via a managed block in a completions hook
# file sourced before `compinit`. Clone, existing-install detection, update, and
# clone removal are all handled by the framework's git-clone method; the hooks
# below only manage the fpath block in the hook file(s).
#
# The hook file defaults to setup-shell's `sys_shellcompletions` path
# ($(shell__detect_zshdir)/shellcompletions) — a multi-writer region sourced by
# setup-shell's zshrc pre-compinit block. When setup-shell's `sys_shellcompletions`
# is customized, set a matching `rcfile` here.

_IZC_MARKER="install-zsh-completion-fpath"

_izc_rcfiles() {
  # Print resolved hook-file paths, one per line. An empty rcfile resolves to
  # setup-shell's default sys_shellcompletions path for the current distro.
  if [ -n "${RCFILE:-}" ]; then
    local _f
    for _f in ${RCFILE}; do
      [ -n "$_f" ] && printf '%s\n' "$_f"
    done
    return 0
  fi
  printf '%s/shellcompletions\n' "$(shell__detect_zshdir)"
}

_izc_sync_fpath_blocks() {
  # Write (or refresh) the managed fpath block in every hook file.
  local _rc
  while IFS= read -r _rc; do
    [ -n "$_rc" ] || continue
    file__mkdir "$(dirname "$_rc")"
    shell__write_block --file "$_rc" --marker "${_IZC_MARKER}" \
      --content "fpath=( \"${_RESOLVED_PREFIX}/src\" \${fpath[@]} )"
    logging__success "  zsh-completions fpath → ${_rc}"
  done < <(_izc_rcfiles)
}

# shellcheck disable=SC2329,SC2317
__install_run_git_clone_post() { _izc_sync_fpath_blocks; }

# shellcheck disable=SC2329,SC2317
__update_run_git_clone_post() { _izc_sync_fpath_blocks; }

# shellcheck disable=SC2329,SC2317
__uninstall_finish_post() {
  # Strip the fpath block from every hook file; delete a hook file only when it
  # is whitespace-only afterwards (setup-shell's and other features' markers in
  # the same multi-writer file keep it alive).
  local _rc
  while IFS= read -r _rc; do
    [ -n "$_rc" ] || continue
    [ -f "$_rc" ] || continue
    shell__sync_block --files "$_rc" --marker "${_IZC_MARKER}"
    if [ -f "$_rc" ] && ! grep -qv '^[[:space:]]*$' "$_rc" 2> /dev/null; then
      file__rm "$_rc"
    fi
  done < <(_izc_rcfiles)
}
