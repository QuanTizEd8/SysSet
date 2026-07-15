# shellcheck shell=bash

# ===========================================================================
# Deploy-gate predicates
# ===========================================================================

_should_deploy() {
  local _shell="$1" _mode
  case "$_shell" in
    bash) _mode="${SETUP_BASH}" ;;
    zsh) _mode="${SETUP_ZSH}" ;;
  esac
  case "$_mode" in
    true) return 0 ;;
    false) return 1 ;;
    auto) command -v "$_shell" > /dev/null 2>&1 ;;
  esac
}

_setup_bash_env() {
  case "${SETUP_BASH_ENV}" in
    false) return 1 ;;
    true) return 0 ;;
    auto) _should_deploy bash ;;
  esac
}

_deploy_system() {
  case "${SETUP_SYSTEM}" in
    true) return 0 ;;
    false) return 1 ;;
    auto) users__is_privileged ;;
  esac
}

_deploy_skel() {
  case "${SETUP_SKEL}" in
    true) return 0 ;;
    false) return 1 ;;
    # auto: only deploy when privileged and /etc/skel already exists (not on macOS).
    auto) users__is_privileged && [ -d /etc/skel ] ;;
  esac
}

# ===========================================================================
# Target when-gates (referenced by _internal.targets[].when)
# ===========================================================================

_ss_target_system_shared() { _deploy_system; }
_ss_target_system_bash() { _deploy_system && _should_deploy bash; }
_ss_target_system_zsh() { _deploy_system && _should_deploy zsh; }
_ss_target_system_bashenv() { _deploy_system && _setup_bash_env; }
_ss_target_environment_line() { _deploy_system && _setup_bash_env; }
_ss_target_skel_shared() { _deploy_skel && { _should_deploy bash || _should_deploy zsh; }; }
_ss_target_skel_bash() { _deploy_skel && _should_deploy bash; }
_ss_target_skel_zsh() { _deploy_skel && _should_deploy zsh; }
_ss_target_user_shared() { _should_deploy bash || _should_deploy zsh; }
_ss_target_user_bash() { _should_deploy bash; }
_ss_target_user_zsh() { _should_deploy zsh; }

# ===========================================================================
# System path resolvers (referenced by _internal.targets[].path_resolver)
# ===========================================================================

_ss_resolve_sys_bashrc() { shell__detect_bashrc; }

_ss_resolve_sys_bashenv() {
  if [ -n "${SYS_BASHENV:-}" ]; then
    printf '%s' "${SYS_BASHENV}"
    return 0
  fi
  local _brc
  _brc="$(shell__detect_bashrc)"
  if [[ "$_brc" == "/etc/bash.bashrc" || "$_brc" == "/etc/bashrc" ]]; then
    printf '/etc/bashenv'
  else
    printf '%s/bashenv' "$(dirname "$_brc")"
  fi
}

_ss_resolve_sys_zshenv() { printf '%s/zshenv' "$(shell__detect_zshdir)"; }
_ss_resolve_sys_zprofile() { printf '%s/zprofile' "$(shell__detect_zshdir)"; }
_ss_resolve_sys_zshrc() { printf '%s/zshrc' "$(shell__detect_zshdir)"; }

_ss_resolve_sys_shellcompletions() {
  if [ -n "${SYS_SHELLCOMPLETIONS:-}" ]; then
    printf '%s' "${SYS_SHELLCOMPLETIONS}"
  else
    printf '%s/shellcompletions' "$(shell__detect_zshdir)"
  fi
}

# ===========================================================================
# Skel path resolvers
# ===========================================================================

_ss_resolve_skel_shellenv() {
  local _rel
  _rel="$(_user_file_skel_rel_path "${USER_SHELLENV}")" || return 1
  printf '/etc/skel/%s' "$_rel"
}
_ss_resolve_skel_shellrc() {
  local _rel
  _rel="$(_user_file_skel_rel_path "${USER_SHELLRC}")" || return 1
  printf '/etc/skel/%s' "$_rel"
}
_ss_resolve_skel_zshrc() {
  local _zrel
  _zrel="$(_normalize_zdotdir_for_skel)" || return 1
  printf '/etc/skel/%s/.zshrc' "$_zrel"
}
_ss_resolve_skel_zprofile() {
  local _zrel
  _zrel="$(_normalize_zdotdir_for_skel)" || return 1
  printf '/etc/skel/%s/.zprofile' "$_zrel"
}

# ===========================================================================
# User path resolvers (require _SS_USER / _SS_ZDOTDIR context)
# ===========================================================================

_ss_resolve_user_shellenv() { _user_file_deploy_path "${_SS_USER}" "${USER_SHELLENV}"; }
_ss_resolve_user_shellrc() { _user_file_deploy_path "${_SS_USER}" "${USER_SHELLRC}"; }
_ss_resolve_user_bash_profile() { printf '%s/.bash_profile' "$(users__resolve_home "${_SS_USER}")"; }
_ss_resolve_user_bashrc() { printf '%s/.bashrc' "$(users__resolve_home "${_SS_USER}")"; }
_ss_resolve_user_zshenv() { printf '%s/.zshenv' "$(users__resolve_home "${_SS_USER}")"; }
_ss_resolve_user_zprofile() { printf '%s/.zprofile' "${_SS_ZDOTDIR}"; }
_ss_resolve_user_zshrc() { printf '%s/.zshrc' "${_SS_ZDOTDIR}"; }

# ===========================================================================
# Line-target resolver (prints KEY<TAB>VALUE)
# ===========================================================================

_ss_line_bash_env() { printf 'BASH_ENV\t%s' "$(_ss_resolve_sys_bashenv)"; }

# ===========================================================================
# User-file path helpers
# ===========================================================================

_user_file_deploy_path() {
  # Install-time absolute path for a per-user relative filename/expression.
  # Plain relative names (`.shellenv`, `.config/env/shell`) are joined to the
  # user's home — users__expand_path's fast path returns non-`$`/non-`~` strings
  # unchanged, so it must not be relied on to prepend HOME here.
  local _username="$1" _rel="$2"
  [[ -n "$_rel" ]] || return 1
  # XDG_CONFIG_HOME is injected so a `${XDG_CONFIG_HOME:-…}` expression (e.g. the
  # default user_bashtheme) resolves to the configured XDG location — the same
  # value the deployed shellenv exports at runtime. _SS_XDG_CONFIG_HOME is set by
  # _ss_set_user_context before this runs; if unset, an empty value degrades the
  # `${XDG_CONFIG_HOME:-…}` fallback to the prior <home>/.config behavior.
  case "$_rel" in
    /*) printf '%s' "$_rel" ;;
    '~'*) users__expand_path --user "$_username" "$_rel" ;;
    '$'*) users__expand_path --user "$_username" \
      --env "HOME=$(users__resolve_home "$_username")" \
      --env "XDG_CONFIG_HOME=${_SS_XDG_CONFIG_HOME:-}" "$_rel" ;;
    *) printf '%s/%s' "$(users__resolve_home "$_username")" "$_rel" ;;
  esac
}

# shellcheck disable=SC2016  # '$HOME' / '${XDG_CONFIG_HOME}' are literals to strip, not expansions
_ss_xdg_config_rel() {
  # Print the effective XDG_CONFIG_HOME location relative to $HOME, honoring the
  # `block_sys_shellenv_xdg_config_home` option (default `.config`) — the same
  # value the deployed /etc/shellenv exports at runtime. A leading `~/`, `$HOME/`,
  # or `${HOME}/` is stripped so the result is a plain HOME-relative path.
  local _xdg="${BLOCK_SYS_SHELLENV_XDG_CONFIG_HOME:-.config}"
  _xdg="${_xdg#\~/}"
  _xdg="${_xdg#\$HOME/}"
  _xdg="${_xdg#\$\{HOME\}/}"
  printf '%s' "$_xdg"
}

# shellcheck disable=SC2016  # single-quoted '$HOME' etc. are case patterns, not expansions
_user_file_skel_rel_path() {
  # /etc/skel-relative path for a per-user filename/expression. Fails for
  # absolute paths (cannot be mirrored under /etc/skel).
  local _rel="$1"
  case "$_rel" in
    '') return 1 ;;
    /*) return 1 ;;
    '~'/*) printf '%s' "${_rel#\~/}" ;;
    '$HOME'/*) printf '%s' "${_rel#\$HOME/}" ;;
    '${HOME}'/*) printf '%s' "${_rel#\$\{HOME\}/}" ;;
    '${XDG_CONFIG_HOME}'/*)
      printf '%s/%s' "$(_ss_xdg_config_rel)" "${_rel#\$\{XDG_CONFIG_HOME\}/}"
      ;;
    *) printf '%s' "$_rel" ;;
  esac
}

_normalize_zdotdir_for_skel() {
  # /etc/skel-relative subdir for ZDOTDIR files (.zshrc/.zprofile).
  # Fails for absolute ZDOTDIR (cannot be mirrored under /etc/skel).
  # The tilde in the case pattern must be quoted: unquoted `~/*` undergoes
  # tilde expansion to the installer's own home and never matches the literal.
  # The default follows the effective XDG_CONFIG_HOME so a new user seeded from
  # skel finds its zsh layout where their (custom-XDG) ZDOTDIR resolves.
  case "${ZDOTDIR-}" in
    '') printf '%s/zsh' "$(_ss_xdg_config_rel)" ;;
    '~'/*) printf '%s' "${ZDOTDIR#\~/}" ;;
    /*) return 1 ;;
    *) printf '%s' "${ZDOTDIR}" ;;
  esac
}

# ===========================================================================
# Source-expression helpers (four-branch: absolute / expr / ~ / relative)
#
# These emit shell source-lines as literal strings; the single-quoted `$HOME`
# etc. are intentional (they expand at runtime in the deployed file), hence the
# SC2016 disables.
# ===========================================================================

# shellcheck disable=SC2016
_ss_source_expr() {
  local _path="$1"
  case "$_path" in
    /*) printf '. "%s"' "$_path" ;;
    '~'/* | '$'*) printf '[ -f "%s" ] && . "%s"' "$_path" "$_path" ;;
    *) printf '[ -f "$HOME/%s" ] && . "$HOME/%s"' "$_path" "$_path" ;;
  esac
}

# shellcheck disable=SC2016
_ss_source_expr_zsh() {
  local _path="$1"
  case "$_path" in
    /*) printf '[ -f "%s" ] && source "%s"' "$_path" "$_path" ;;
    '~'/* | '$'*) printf '[ -f "%s" ] && source "%s"' "$_path" "$_path" ;;
    *) printf '[ -f "$HOME/%s" ] && . "$HOME/%s"' "$_path" "$_path" ;;
  esac
}

# shellcheck disable=SC2016
_ss_source_expr_zsh_emulate() {
  local _path="$1"
  case "$_path" in
    /*) printf '[ -f "%s" ] && emulate sh -c ". \\"%s\\""' "$_path" "$_path" ;;
    '~'/* | '$'*) printf '[ -f "%s" ] && emulate sh -c ". \\"%s\\""' "$_path" "$_path" ;;
    *) printf '[ -f "$HOME/%s" ] && emulate sh -c ". \\"$HOME/%s\\""' "$_path" "$_path" ;;
  esac
}

_ss_user_shell_source_path() {
  # In user context, resolve to an absolute path; in skel context (_SS_USER
  # unset), keep the literal relative expression so it resolves per new user.
  local _rel="$1"
  [[ -n "$_rel" ]] || return 1
  if [ -z "${_SS_USER:-}" ]; then
    printf '%s' "$_rel"
  else
    _user_file_deploy_path "${_SS_USER}" "$_rel"
  fi
}

# ===========================================================================
# Dynamic block content — system sources
# ===========================================================================

_dyn_source_sys_shellenv() {
  [[ -n "${SYS_SHELLENV:-}" ]] || return 0
  printf '. "%s"' "${SYS_SHELLENV}"
}
_dyn_source_sys_shellenv_zsh() {
  [[ -n "${SYS_SHELLENV:-}" ]] || return 0
  printf "emulate sh -c 'source \"%s\"'" "${SYS_SHELLENV}"
}
_dyn_source_sys_shellrc() {
  [[ -n "${SYS_SHELLRC:-}" ]] || return 0
  printf '. "%s"' "${SYS_SHELLRC}"
}
_dyn_source_sys_shellaliases() {
  [[ -n "${SYS_SHELLALIASES:-}" ]] || return 0
  printf '. "%s"' "${SYS_SHELLALIASES}"
}
_dyn_source_sys_shellcompletions() {
  local _p
  _p="$(_ss_resolve_sys_shellcompletions)"
  [[ -n "$_p" ]] || return 0
  printf '[ -f "%s" ] && . "%s"' "$_p" "$_p"
}
# shellcheck disable=SC2016
_dyn_shellcompletions_fpath_baseline() {
  printf 'fpath=( "%s/completions" "${HOME}/.zfunc" ${fpath[@]} )' "$(shell__detect_zshdir)"
}

# ===========================================================================
# Dynamic block content — /etc/shellenv value blocks
# ===========================================================================

_dyn_shellenv_umask() {
  [[ -n "${BLOCK_SYS_SHELLENV_UMASK:-}" ]] && printf 'umask %s' "${BLOCK_SYS_SHELLENV_UMASK}"
}

_dyn_shellenv_locale() {
  local _v="${BLOCK_SYS_SHELLENV_LOCALE:-}"
  [[ -n "$_v" ]] && printf 'export LANG="%s"\nexport LC_ALL="%s"' "$_v" "$_v"
}

_dyn_shellenv_editor() {
  case "${BLOCK_SYS_SHELLENV_EDITOR:-auto}" in
    skip | '') return 0 ;;
    auto)
      # shellcheck disable=SC2016
      printf '%s' 'if [ -z "${VISUAL}" ] && [ -z "${EDITOR}" ]; then
    if command -v nano >/dev/null 2>&1; then
        export VISUAL=nano EDITOR=nano
    else
        export VISUAL=vi EDITOR=vi
    fi
fi'
      ;;
    neovim) printf 'export VISUAL=nvim EDITOR=nvim' ;;
    code) printf 'export VISUAL="code --wait" EDITOR="code --wait"' ;;
    *) printf 'export VISUAL=%s EDITOR=%s' "${BLOCK_SYS_SHELLENV_EDITOR}" "${BLOCK_SYS_SHELLENV_EDITOR}" ;;
  esac
}

# _args is a plain string; SC2128/SC2178 are false positives from the quoted
# append pattern. SC2016 is intentional (single-quoted runtime shell literals).
# shellcheck disable=SC2016,SC2128,SC2178
_dyn_shellenv_path_baseline() {
  local _v="${BLOCK_SYS_SHELLENV_PATH_BASELINE:-}"
  [[ -n "$_v" ]] || return 0
  # Build one `extend_path --prepend "d1" "d2" …` line from the space-separated
  # dir list (noglob so entries aren't glob-expanded), then the non-root append.
  local _args="" _d _restore_glob=""
  case "$-" in *f*) ;; *)
    _restore_glob=1
    set -f
    ;;
  esac
  for _d in $_v; do
    _args="${_args} \"${_d}\""
  done
  [[ -n "$_restore_glob" ]] && set +f
  printf 'extend_path --prepend%s\n' "$_args"
  printf 'if [ "$(id -u)" -ne 0 ]; then\n    extend_path --append "/usr/games"\nfi'
}

_dyn_shellenv_xdg_data_dirs() {
  local _v="${BLOCK_SYS_SHELLENV_XDG_DATA_DIRS:-}"
  [[ -n "$_v" ]] && printf 'export XDG_DATA_DIRS="%s"' "$_v"
}
_dyn_shellenv_xdg_config_dirs() {
  local _v="${BLOCK_SYS_SHELLENV_XDG_CONFIG_DIRS:-}"
  [[ -n "$_v" ]] && printf 'export XDG_CONFIG_DIRS="%s"' "$_v"
}
# shellcheck disable=SC2016
_dyn_shellenv_xdg_cache_home() {
  local _v="${BLOCK_SYS_SHELLENV_XDG_CACHE_HOME:-}"
  [[ -n "$_v" ]] && printf 'export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/%s}"' "$_v"
}
# shellcheck disable=SC2016
_dyn_shellenv_xdg_config_home() {
  local _v="${BLOCK_SYS_SHELLENV_XDG_CONFIG_HOME:-}"
  [[ -n "$_v" ]] && printf 'export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/%s}"' "$_v"
}
# shellcheck disable=SC2016
_dyn_shellenv_xdg_data_home() {
  local _v="${BLOCK_SYS_SHELLENV_XDG_DATA_HOME:-}"
  [[ -n "$_v" ]] && printf 'export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/%s}"' "$_v"
}
# shellcheck disable=SC2016
_dyn_shellenv_xdg_state_home() {
  local _v="${BLOCK_SYS_SHELLENV_XDG_STATE_HOME:-}"
  [[ -n "$_v" ]] && printf 'export XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/%s}"' "$_v"
}

# ===========================================================================
# Dynamic block content — /etc/environment BASH_ENV
# ===========================================================================

_dyn_environment_bash_env() { printf 'BASH_ENV=%s' "$(_ss_resolve_sys_bashenv)"; }

# ===========================================================================
# Dynamic block content — user/skel dotfiles
# ===========================================================================

# _out is a plain string; SC2178/SC2179 are false positives on the quoted
# append pattern. SC2016 is intentional (single-quoted runtime shell literals).
# shellcheck disable=SC2016,SC2178,SC2179
_dyn_user_shellenv_xdg() {
  # User XDG exports for ~/.shellenv, derived from the same four options as the
  # system shellenv XDG blocks and guarded with ${VAR:-…} so a value exported
  # earlier (custom env, system shellenv customization) is never clobbered.
  # Empty option values omit that variable's line.
  local _out="" _v
  _v="${BLOCK_SYS_SHELLENV_XDG_DATA_HOME:-}"
  [[ -n "$_v" ]] && _out+="export XDG_DATA_HOME=\"\${XDG_DATA_HOME:-\${HOME}/${_v}}\""$'\n'
  _v="${BLOCK_SYS_SHELLENV_XDG_CONFIG_HOME:-}"
  [[ -n "$_v" ]] && _out+="export XDG_CONFIG_HOME=\"\${XDG_CONFIG_HOME:-\${HOME}/${_v}}\""$'\n'
  _v="${BLOCK_SYS_SHELLENV_XDG_STATE_HOME:-}"
  [[ -n "$_v" ]] && _out+="export XDG_STATE_HOME=\"\${XDG_STATE_HOME:-\${HOME}/${_v}}\""$'\n'
  _v="${BLOCK_SYS_SHELLENV_XDG_CACHE_HOME:-}"
  [[ -n "$_v" ]] && _out+="export XDG_CACHE_HOME=\"\${XDG_CACHE_HOME:-\${HOME}/${_v}}\""$'\n'
  printf '%s' "${_out%$'\n'}"
}

_dyn_user_bashprofile_shellenv() {
  local _p
  _p="$(_ss_user_shell_source_path "${USER_SHELLENV}")" || return 0
  _ss_source_expr "$_p"
}
_dyn_user_bashrc_shellrc() {
  local _p
  _p="$(_ss_user_shell_source_path "${USER_SHELLRC}")" || return 0
  _ss_source_expr "$_p"
}
_dyn_user_bashrc_bashtheme() { _ss_bash_theme_source_content; }

_dyn_user_zshenv_shellenv() {
  local _p
  _p="$(_ss_user_shell_source_path "${USER_SHELLENV}")" || return 0
  _ss_source_expr_zsh_emulate "$_p"
}
# shellcheck disable=SC2016
_dyn_user_zshenv_zdotdir() {
  if [ -n "${_SS_USER:-}" ]; then
    printf 'export ZDOTDIR="%s"' "${_SS_ZDOTDIR}"
    return 0
  fi
  # Skel context: literal, runtime-resolved expression.
  if [ -z "${ZDOTDIR:-}" ]; then
    printf 'export ZDOTDIR="${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"'
    return 0
  fi
  case "${ZDOTDIR}" in
    '~'/*) printf 'export ZDOTDIR="${ZDOTDIR:-$HOME/%s}"' "${ZDOTDIR#\~/}" ;;
    /*) printf 'export ZDOTDIR="%s"' "${ZDOTDIR}" ;;
    *) printf 'export ZDOTDIR="${ZDOTDIR:-$HOME/%s}"' "${ZDOTDIR}" ;;
  esac
}
_dyn_user_zshrc_zshtheme() {
  [[ -n "${USER_ZSHTHEME:-}" ]] || return 0
  case "${USER_ZSHTHEME}" in
    '~'/*)
      if [ -n "${_SS_USER:-}" ]; then
        local _expr
        _expr="$(users__expand_path --user "${_SS_USER}" "${USER_ZSHTHEME}")" || return 1
        _ss_source_expr_zsh "$_expr"
      else
        _ss_source_expr_zsh "${USER_ZSHTHEME}"
      fi
      ;;
    *) _ss_source_expr_zsh "${USER_ZSHTHEME}" ;;
  esac
}
_dyn_user_zshrc_shellrc() {
  local _p
  _p="$(_ss_user_shell_source_path "${USER_SHELLRC}")" || return 0
  _ss_source_expr "$_p"
}

# shellcheck disable=SC2016
_ss_bash_theme_source_content() {
  [[ -n "${USER_BASHTHEME:-}" ]] || return 0
  local _expr
  case "${USER_BASHTHEME}" in
    '~'/*)
      if [ -n "${_SS_USER:-}" ]; then
        _expr="$(users__expand_path --user "${_SS_USER}" "${USER_BASHTHEME}")" || return 1
      else
        _expr="${USER_BASHTHEME}"
      fi
      ;;
    *) _expr="${USER_BASHTHEME}" ;;
  esac
  printf '_BASH_THEME="%s"\n[ -f "$_BASH_THEME" ] && . "$_BASH_THEME"\nunset _BASH_THEME' "$_expr"
}

# ===========================================================================
# Engine sourcing + user context
# ===========================================================================

_ss__source_engine() {
  # shellcheck source=files/lifecycle.bash disable=SC1091
  source "${_FEAT_FILES_DIR}/lifecycle.bash"
  _ss__load_registry
}

_ss_set_user_context() {
  # Populate the _SS_* globals the user path resolvers and dynamic blocks read.
  local _user="$1"
  _SS_USER="$_user"
  local _home
  _home="$(users__resolve_home "$_user")"
  # Honor the configured XDG_CONFIG_HOME (block_sys_shellenv_xdg_config_home) so
  # theme scaffolds and ZDOTDIR land where the deployed shellenv points at
  # runtime; defaults to <home>/.config when the option is unset.
  _SS_XDG_CONFIG_HOME="${_home}/$(_ss_xdg_config_rel)"
  if [ -z "${ZDOTDIR-}" ]; then
    _SS_ZDOTDIR="${_SS_XDG_CONFIG_HOME}/zsh"
  else
    _SS_ZDOTDIR="$(users__expand_path --user "$_user" "$ZDOTDIR")"
  fi
}

_ss__resolve_user_list() {
  # Print one resolved username per line — the same list
  # __feat_do_configure_users__ resolves — so the fail-mode user probe matches
  # the real apply pass (not a bare, option-blind users__resolve_list).
  local -a _ul_args=()
  [[ -v ADD_CURRENT_USER ]] && _ul_args+=(--current "${ADD_CURRENT_USER}")
  [[ -v ADD_REMOTE_USER ]] && _ul_args+=(--remote "${ADD_REMOTE_USER}")
  [[ -v ADD_CONTAINER_USER ]] && _ul_args+=(--container "${ADD_CONTAINER_USER}")
  if [[ -v ADD_USERS ]]; then
    local _u
    for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do
      _ul_args+=(--user "${_u}")
    done
  fi
  users__resolve_list "${_ul_args[@]}" 2> /dev/null || true
}

_ss__probe_users() {
  # Fail-mode probe for user-scope targets, using the same resolved user list as
  # the real apply pass (not a bare users__resolve_list). Collect-only: appends
  # to _SS_CONFLICTS (reset by _ss__probe_pass); the caller reports afterwards.
  [[ "${IF_EXISTS_USER}" == fail ]] || return 0
  local -a _users=()
  mapfile -t _users < <(_ss__resolve_user_list)
  local _u _tid _scope _path _mode
  for _u in "${_users[@]}"; do
    [[ -n "$_u" ]] || continue
    id "$_u" > /dev/null 2>&1 || continue
    _ss_set_user_context "$_u"
    for _tid in "${_FEAT_SS_TARGET_ORDER[@]}"; do
      _scope="${_FEAT_SS_TARGET_SCOPE[$_tid]}"
      [[ "$_scope" == user ]] || continue
      _ss__when_passes "${_FEAT_SS_TARGET_WHEN[$_tid]:-}" || continue
      local _deploy="${_FEAT_SS_TARGET_DEPLOY_OPTION[$_tid]:-}"
      [[ -n "$_deploy" ]] && _ss__deploy_path_empty "$_deploy" && continue
      _path="$(_ss__resolve_target_path "$_tid")" || continue
      [[ -n "$_path" ]] || continue
      _ss__probe_target "$_tid" "$_path" fail
    done
  done
}

# ===========================================================================
# Framework hooks
# ===========================================================================

__init_args_post() {
  # Route uninstall vs install through the framework dispatch by setting the
  # synthetic IF_EXISTS the framework's __main__ checks for. Our
  # __if_exists_dispatch__ override then routes purely on this synthetic value.
  # setup-shell's real lifecycle knobs are if_exists_sys/_skel/_user; the shared
  # framework `if_exists` option (emitted by metadata.shared.yaml) is otherwise
  # ignored, but we still honor `if_exists=uninstall` as an uninstall trigger so
  # the dangerous case is not silently a no-op.
  if [[ "${IF_EXISTS_SYS:-}" == uninstall || "${IF_EXISTS:-}" == uninstall ]]; then
    IF_EXISTS=uninstall
  else
    IF_EXISTS=reinstall
  fi
}

__if_exists_dispatch__() {
  # Full override: never consult _FEAT_EXISTING (setup-shell has no binary and
  # applies per-target lifecycle regardless of prior-install detection), and
  # never reach the framework's METHOD/version-oriented __update_run__/
  # __reinstall_run__ (which fatal without a METHOD this feature does not have).
  if [[ "${IF_EXISTS}" == uninstall ]]; then
    __uninstall__
  else
    __install__
  fi
  exit 0
}

__detect_existing_path_post() {
  # Logging only — the dispatch override does not gate on _FEAT_EXISTING.
  if [ -f /etc/shellenv ] || grep -rqlF '# >>> setup-shell-' /etc 2> /dev/null; then
    _FEAT_EXISTING=true
    logging__detect "Found existing setup-shell configuration (managed markers present)."
  fi
}

__configure_user() {
  local _cu_username="$1"
  _ss_set_user_context "$_cu_username"
  local _cu_home _cu_group
  _cu_home="$(users__resolve_home "$_cu_username")"
  _cu_group="$(users__primary_group_of "$_cu_username" 2> /dev/null || echo "$_cu_username")"

  local _user_mode
  _user_mode="$(_ss__target_mode_for user)"

  if [ ! -d "$_cu_home" ] && [[ "$_user_mode" != uninstall ]]; then
    logging__warn "Home directory '${_cu_home}' does not exist for user '${_cu_username}' — creating."
    file__mkdir "$_cu_home"
    file__chown "${_cu_username}:${_cu_group}" "$_cu_home"
  fi

  logging__info "Configuring user '${_cu_username}' (home: ${_cu_home}, mode: ${_user_mode})..."

  local _tid _scope _deploy _path _mode
  local -a _cu_chown_paths=()
  for _tid in "${_FEAT_SS_TARGET_ORDER[@]}"; do
    _scope="${_FEAT_SS_TARGET_SCOPE[$_tid]}"
    [[ "$_scope" == user ]] || continue
    _ss__when_passes "${_FEAT_SS_TARGET_WHEN[$_tid]:-}" || continue
    _deploy="${_FEAT_SS_TARGET_DEPLOY_OPTION[$_tid]:-}"
    [[ -n "$_deploy" ]] && _ss__deploy_path_empty "$_deploy" && continue
    _path="$(_ss__resolve_target_path "$_tid")" || continue
    [[ -n "$_path" ]] || continue
    _mode="$(_ss__target_mode_for user)"
    _ss__apply_target "$_tid" "$_path" "$_mode"
    if [[ "$_mode" != uninstall ]]; then
      _cu_chown_paths+=("$_path")
      local _parent
      _parent="$(dirname "$_path")"
      # Walk up to the home dir. The `/*` guard also stops immediately on any
      # non-absolute path (dirname of a relative path can loop on ".").
      while [[ "$_parent" == /* && "$_parent" != "$_cu_home" && "$_parent" != "/" ]]; do
        _cu_chown_paths+=("$_parent")
        _parent="$(dirname "$_parent")"
      done
    fi
  done

  # Theme scaffolds: empty files created for downstream features (starship,
  # oh-my-zsh, oh-my-bash) to append their own guarded blocks to. Created/removed
  # independently of the source-hook block that references them.
  if _should_deploy bash && [ -n "${USER_BASHTHEME:-}" ]; then
    local _bt
    _bt="$(_user_file_deploy_path "$_cu_username" "${USER_BASHTHEME}")"
    if [[ "$_user_mode" == uninstall ]]; then
      [ -f "$_bt" ] && file__rm "$_bt"
    else
      file__mkdir "$(dirname "$_bt")"
      [ -f "$_bt" ] || printf '' | file__tee "$_bt"
      _cu_chown_paths+=("$(dirname "$_bt")" "$_bt")
    fi
  fi
  if _should_deploy zsh && [ -n "${USER_ZSHTHEME:-}" ]; then
    local _zt
    _zt="$(users__expand_path --user "$_cu_username" \
      --env "ZDOTDIR=${_SS_ZDOTDIR}" --env "XDG_CONFIG_HOME=${_SS_XDG_CONFIG_HOME}" \
      "${USER_ZSHTHEME}")"
    if [[ "$_user_mode" == uninstall ]]; then
      [ -f "$_zt" ] && file__rm "$_zt"
    else
      file__mkdir "$(dirname "$_zt")"
      [ -f "$_zt" ] || printf '' | file__tee "$_zt"
      _cu_chown_paths+=("$_zt")
    fi
  fi

  if [[ "$_user_mode" != uninstall ]] && ((${#_cu_chown_paths[@]})); then
    _cu_chown_paths+=("$_cu_home")
    local _p
    for _p in "${_cu_chown_paths[@]}"; do
      [ -e "$_p" ] || continue
      file__chown "${_cu_username}:${_cu_group}" "$_p" 2> /dev/null || true
    done
  fi

  logging__success "User '${_cu_username}' configuration complete."
  return 0
}

__install_run__() {
  _ss__source_engine
  _ss__resolve_lifecycle_modes

  # Fail-mode: probe every fail-scoped target (system/skel + users) before any
  # write, then report all collected conflicts at once. A conflict in ANY scope
  # aborts the whole run with zero writes.
  _ss__probe_pass
  _ss__probe_users
  _ss__report_fail_conflicts || exit 1

  logging__info "Applying setup-shell registry targets..."
  _ss__apply_pass
  return 0
}

__uninstall_run__() {
  __run_feature_hook__ __uninstall_run_pre
  _ss__source_engine
  IF_EXISTS_SYS=uninstall
  IF_EXISTS_SKEL=uninstall
  IF_EXISTS_USER=uninstall
  logging__info "Removing setup-shell managed content..."
  _ss__apply_pass
  __feat_do_configure_users__
  __run_feature_hook__ __uninstall_run_post
}
