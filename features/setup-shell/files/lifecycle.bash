# shellcheck shell=bash
# Setup-shell lifecycle engine — registry-driven apply/probe/uninstall.
#
# The block/target registry (files/blocks.registry.bash) is generated at build
# time from _internal.blocks / _internal.targets in metadata.yaml. It populates
# the _FEAT_SS_BLOCK_* / _FEAT_SS_TARGET_* associative arrays and the
# _FEAT_SS_TARGET_ORDER indexed array this engine reads.
#
# Per-mode semantics (per target, per block):
#   skip      absent → assemble enabled blocks; exists → zero writes.
#   update    absent → assemble; exists → inject/sync-if-different/remove per block.
#   reinstall whole-file replace from enabled blocks; back up existing file first.
#   fail      probe pass first (dry-run all fail-scoped targets); abort with zero
#             writes if any would-write to an existing target; else apply as update.
#   uninstall strip every block marker; delete file iff whitespace-only afterwards.

_ss__load_registry() {
  # shellcheck source=blocks.registry.bash disable=SC1091
  source "${_FEAT_FILES_DIR}/blocks.registry.bash"
}

# --- Lifecycle mode resolution -------------------------------------------- #

_ss__resolve_if_exists_scope() {
  # Resolve a single if_exists_* variable when its value is "auto".
  local _var="$1"
  local -n _ref="${_var}"
  [[ -v "${_var}" ]] || return 0
  [[ "${_ref}" == "auto" ]] || return 0
  if os__is_devcontainer_build; then
    _ref=reinstall
    logging__info "Resolved ${_var}=auto → reinstall (devcontainer build)."
  else
    _ref=update
    logging__info "Resolved ${_var}=auto → update (standalone)."
  fi
}

_ss__resolve_lifecycle_modes() {
  # Resolve IF_EXISTS_SYS first, then let SKEL/USER inherit it (or resolve their
  # own auto). "inherit" (the default) copies the already-resolved IF_EXISTS_SYS.
  _ss__resolve_if_exists_scope IF_EXISTS_SYS
  if [[ -z "${IF_EXISTS_SKEL:-}" || "${IF_EXISTS_SKEL}" == inherit ]]; then
    IF_EXISTS_SKEL="${IF_EXISTS_SYS}"
  else
    _ss__resolve_if_exists_scope IF_EXISTS_SKEL
  fi
  if [[ -z "${IF_EXISTS_USER:-}" || "${IF_EXISTS_USER}" == inherit ]]; then
    IF_EXISTS_USER="${IF_EXISTS_SYS}"
  else
    _ss__resolve_if_exists_scope IF_EXISTS_USER
  fi
}

_ss__target_mode_for() {
  local _scope="$1"
  case "$_scope" in
    system | line) printf '%s' "${IF_EXISTS_SYS}" ;;
    skel) printf '%s' "${IF_EXISTS_SKEL}" ;;
    user) printf '%s' "${IF_EXISTS_USER}" ;;
    *) printf '%s' "${IF_EXISTS_SYS}" ;;
  esac
}

# --- Precondition (v1 stub — deferred, always eligible) ------------------- #

_block_precondition_met() {
  # v1 stub — block preconditions deferred. Reserved so a later session can add
  # content-based duplicate-detection without changing this call site.
  local _precondition="${1:-}"
  [[ -n "$_precondition" ]] && logging__debug "Block precondition '${_precondition}' deferred (v1)."
  return 0
}

# --- Registry accessors --------------------------------------------------- #

_ss__when_passes() {
  local _expr="$1"
  [[ -z "$_expr" || "$_expr" == "true" ]] && return 0
  "$_expr"
}

_ss__block_enabled() {
  # A block is enabled when its option is set to an "included" value. Blocks with
  # no option are always enabled (preambles). Rules by option_type:
  #   boolean  → value == true (default true when unset)
  #   string   → value non-empty
  #   enum     → value non-empty and not the "skip" sentinel (editor only)
  local _bid="$1"
  local _option="${_FEAT_SS_BLOCK_OPTION[$_bid]:-}"
  [[ -n "$_option" ]] || return 0
  local _type="${_FEAT_SS_BLOCK_OPTION_TYPE[$_bid]:-boolean}"
  local _val="${!_option:-}"
  case "$_type" in
    boolean) [[ "${!_option:-true}" == "true" ]] ;;
    enum) [[ -n "$_val" && "$_val" != "skip" ]] ;;
    string | *) [[ -n "$_val" ]] ;;
  esac
}

_ss__deploy_path_empty() {
  # True when a target's deploy_option is set but resolves to an empty string.
  local _opt="$1"
  [[ -n "$_opt" ]] || return 1
  [[ -z "${!_opt:-}" ]]
}

_ss__resolve_sys_path() {
  local _deploy_opt="$1" _default="$2"
  local _val="${!_deploy_opt:-}"
  if [[ -z "$_val" ]]; then
    printf '%s' "$_default"
  else
    printf '%s' "$_val"
  fi
}

# --- Marker / content helpers --------------------------------------------- #

_ss__marker_present() {
  local _file="$1" _marker="$2"
  grep -qF "# >>> ${_marker} >>>" "$_file" 2> /dev/null
}

_ss__file_whitespace_only() {
  local _file="$1"
  [[ -f "$_file" ]] || return 1
  ! grep -qv '^[[:space:]]*$' "$_file" 2> /dev/null
}

_ss__current_block_body() {
  # Print the exact lines currently between a marker's begin/end comments,
  # matching what shell__write_block would have written as --content. Used to
  # decide whether a sync would actually change bytes (avoids spurious writes on
  # update and spurious conflicts on fail probe). Marker lines are matched with
  # the same normalization shell__write_block uses (_SHELL__AWK_NORM: BOM/CRLF/
  # whitespace) so CRLF or BOM-prefixed foreign files stay comparable.
  local _file="$1" _marker="$2"
  [[ -f "$_file" ]] || return 0
  awk -v begin="# >>> ${_marker} >>>" -v end="# <<< ${_marker} <<<" \
    "${_SHELL__AWK_NORM}"'
    norm($0) == begin { inblock = 1; next }
    inblock && norm($0) == end { inblock = 0; next }
    inblock { body = body sep $0; sep = "\n" }
    END { printf "%s", body }
  ' "$_file"
}

# --- Foreign managed-block preservation (reinstall) ----------------------- #
#
# `reinstall` assembles a fresh file from setup-shell's own enabled blocks and
# replaces the target wholesale. Without preservation this drops any guarded
# block written by another feature or tool (Homebrew's `brew shellenv`, rustup,
# nvm, or a user's own `# >>> … >>>` block) that shares a startup file with us —
# most importantly Homebrew, which must install before the shells (macOS package
# method) and therefore before setup-shell. These helpers carry such blocks over.

_ss__list_managed_markers() {
  # Print the marker of every complete `# >>> M >>> … # <<< M <<<` block in the
  # file, one per line, in first-appearance order, de-duplicated. Marker lines
  # are matched with the same BOM/CRLF/whitespace normalization as the rest of
  # the engine so foreign files with odd line endings still parse.
  local _file="$1"
  [[ -f "$_file" ]] || return 0
  awk "${_SHELL__AWK_NORM}"'
    {
      l = norm($0)
      if (l ~ /^# >>> .+ >>>$/) {
        m = substr(l, 7, length(l) - 10)
        if (!(m in seen)) { seen[m] = 1; order[++n] = m }
        begun[m] = 1
      } else if (l ~ /^# <<< .+ <<<$/) {
        m = substr(l, 7, length(l) - 10)
        if (m in begun) complete[m] = 1
      }
    }
    END { for (i = 1; i <= n; i++) if (complete[order[i]]) print order[i] }
  ' "$_file"
}

_ss__marker_is_own() {
  # True for setup-shell's own markers (regenerated from enabled blocks, so a
  # stale on-disk copy must never be carried over). This prefix is the same
  # discriminator __detect_existing_path_post uses.
  [[ "$1" == setup-shell-* ]]
}

_ss__marker_allowed() {
  # True when MANAGED_BLOCK_MARKERS is empty (allow all) or the marker matches at
  # least one of its newline-separated glob patterns. Patterns may contain spaces
  # (markers do), so lines are read verbatim and matched unquoted inside [[ ]].
  local _m="$1" _pat _has=false
  while IFS= read -r _pat; do
    [[ -n "$_pat" ]] || continue
    _has=true
    # shellcheck disable=SC2053  # RHS is an intentional glob pattern.
    [[ "$_m" == $_pat ]] && return 0
  done <<< "${MANAGED_BLOCK_MARKERS:-}"
  [[ "$_has" == true ]] && return 1
  return 0
}

_ss__block_preserved() {
  # Whether a foreign managed block with this marker should survive a reinstall.
  local _m="$1"
  [[ "${PRESERVE_MANAGED_BLOCKS:-true}" == true ]] || return 1
  _ss__marker_is_own "$_m" && return 1
  _ss__marker_allowed "$_m" || return 1
  return 0
}

_ss__extract_block_region() {
  # Print a marker's full block region — begin line, body, end line — verbatim
  # (original bytes), so the carried-over block is byte-identical to the source.
  local _file="$1" _marker="$2"
  [[ -f "$_file" ]] || return 0
  awk -v marker="$_marker" "${_SHELL__AWK_NORM}"'
    BEGIN { b = "# >>> " marker " >>>"; e = "# <<< " marker " <<<" }
    {
      nl = norm($0)
      if (nl == b) { inblock = 1; print; next }
      if (inblock) { print; if (nl == e) inblock = 0; next }
    }
  ' "$_file"
}

_ss__collect_preserved_blocks() {
  # Concatenate (blank-line separated) every preservable foreign block found in
  # the file. Empty output when preservation is off or nothing qualifies. The
  # caller's $() capture strips the trailing newlines.
  local _file="$1"
  [[ -f "$_file" ]] || return 0
  [[ "${PRESERVE_MANAGED_BLOCKS:-true}" == true ]] || return 0
  local _m _region _sep=""
  while IFS= read -r _m; do
    [[ -n "$_m" ]] || continue
    _ss__block_preserved "$_m" || continue
    _region="$(_ss__extract_block_region "$_file" "$_m")"
    [[ -n "$_region" ]] || continue
    printf '%s%s' "$_sep" "$_region"
    _sep=$'\n\n'
  done < <(_ss__list_managed_markers "$_file")
}

_ss__block_content() {
  # Render a block's content: dynamic → call the resolver fn; fixed → cat slice.
  local _bid="$1"
  local _kind="${_FEAT_SS_BLOCK_KIND[$_bid]:-fixed}"
  local _content=""
  if [[ "$_kind" == "dynamic" ]]; then
    local _dynamic="${_FEAT_SS_BLOCK_DYNAMIC[$_bid]:-}"
    if [[ -n "$_dynamic" ]] && declare -f "$_dynamic" > /dev/null; then
      _content="$("${_dynamic}")"
    fi
  else
    local _slice="${_FEAT_SS_BLOCK_SLICE[$_bid]:-}"
    if [[ -n "$_slice" && -f "${_FEAT_FILES_DIR}/${_slice}" ]]; then
      _content="$(cat "${_FEAT_FILES_DIR}/${_slice}")"
    fi
  fi
  printf '%s' "$_content"
}

# --- Assembler (skip-on-absent, reinstall, fail-apply-on-absent) ---------- #

_ss__assemble_target() {
  # Concatenate every enabled block for a target, in registry order, each
  # wrapped in its marker. Blocks whose `when` fails, precondition fails, are
  # disabled, or render empty are skipped.
  local _tid="$1"
  local _parts="" _content _marker
  local _bid
  for _bid in ${_FEAT_SS_TARGET_BLOCKS[$_tid]}; do
    [[ -n "$_bid" ]] || continue
    _ss__when_passes "${_FEAT_SS_BLOCK_WHEN[$_bid]:-}" || continue
    _block_precondition_met "${_FEAT_SS_BLOCK_PRECONDITION[$_bid]:-}" || continue
    _ss__block_enabled "$_bid" || continue
    _content="$(_ss__block_content "$_bid")"
    [[ -n "$_content" ]] || continue
    _marker="${_FEAT_SS_BLOCK_MARKER[$_bid]}"
    _parts+="# >>> ${_marker} >>>
${_content}
# <<< ${_marker} <<<

"
  done
  printf '%s' "$_parts"
}

# --- Per-block planning (shared by apply and fail probe) ------------------ #

_ss__target_plan_block() {
  # Sets globals: _PLAN_ACTION (noop|inject|sync|remove|assemble|skip),
  #               _PLAN_WOULD_WRITE (true|false).
  # "sync" is only planned when the rendered content differs from what is
  # currently on disk between the markers — an identical re-sync is a no-op
  # (fixes both spurious update writes and spurious fail-probe conflicts).
  local _mode="$1" _file="$2" _bid="$3" _exists="$4"
  _PLAN_ACTION=noop
  _PLAN_WOULD_WRITE=false
  _ss__when_passes "${_FEAT_SS_BLOCK_WHEN[$_bid]:-}" || return 0
  _block_precondition_met "${_FEAT_SS_BLOCK_PRECONDITION[$_bid]:-}" || return 0
  local _marker="${_FEAT_SS_BLOCK_MARKER[$_bid]}"
  local _enabled=0
  _ss__block_enabled "$_bid" && _enabled=1
  local _present=0
  [[ "$_exists" == true ]] && _ss__marker_present "$_file" "$_marker" && _present=1

  case "$_mode" in
    uninstall)
      if ((_present)); then
        _PLAN_ACTION=remove
        _PLAN_WOULD_WRITE=true
      fi
      ;;
    skip)
      if [[ "$_exists" == true ]]; then
        _PLAN_ACTION=skip
      elif ((_enabled)); then
        _PLAN_ACTION=assemble
        _PLAN_WOULD_WRITE=true
      fi
      ;;
    reinstall)
      if ((_enabled)); then
        _PLAN_ACTION=assemble
        _PLAN_WOULD_WRITE=true
      fi
      ;;
    update | fail)
      if [[ "$_exists" != true ]]; then
        if ((_enabled)); then
          _PLAN_ACTION=assemble
          _PLAN_WOULD_WRITE=true
        fi
      elif ((_enabled)) && ! ((_present)); then
        # An enabled block whose content renders empty (e.g. a source hook whose
        # deploy-path option is '') injects nothing — not a write, and must not
        # count as a fail-probe conflict.
        if [[ -n "$(_ss__block_content "$_bid")" ]]; then
          _PLAN_ACTION=inject
          _PLAN_WOULD_WRITE=true
        fi
      elif ((_enabled)) && ((_present)); then
        # Only a real content change counts as a write.
        local _rendered _current
        _rendered="$(_ss__block_content "$_bid")"
        _current="$(_ss__current_block_body "$_file" "$_marker")"
        if [[ "$_rendered" != "$_current" ]]; then
          _PLAN_ACTION=sync
          _PLAN_WOULD_WRITE=true
        fi
      elif ! ((_enabled)) && ((_present)); then
        _PLAN_ACTION=remove
        _PLAN_WOULD_WRITE=true
      fi
      ;;
  esac
}

_ss__do_block_action() {
  # Execute an already-planned per-block action (inject/sync/remove) on a file.
  local _action="$1" _file="$2" _bid="$3"
  local _marker="${_FEAT_SS_BLOCK_MARKER[$_bid]}"
  local _content
  case "$_action" in
    inject)
      _content="$(_ss__block_content "$_bid")"
      [[ -n "$_content" ]] || return 0
      local _anchor="${_FEAT_SS_BLOCK_ANCHOR[$_bid]:-}"
      if [[ -n "$_anchor" && "$_anchor" != eof ]]; then
        local _line
        _line="$(shell__resolve_inject_line_v1 --file "$_file" --anchor "$_anchor")"
        shell__insert_block_at_line --file "$_file" --marker "$_marker" \
          --content "$_content" --line "$_line"
      else
        shell__write_block --file "$_file" --marker "$_marker" --content "$_content"
      fi
      ;;
    sync)
      _content="$(_ss__block_content "$_bid")"
      [[ -n "$_content" ]] || return 0
      shell__write_block --file "$_file" --marker "$_marker" --content "$_content"
      ;;
    remove)
      shell__sync_block --files "$_file" --marker "$_marker"
      ;;
  esac
}

_ss__apply_block() {
  # Plan and apply one block's action to an existing file. `assemble` is a no-op
  # here — whole-file assembly happens at the target level in _ss__apply_target.
  local _mode="$1" _file="$2" _bid="$3" _exists="$4"
  _ss__target_plan_block "$_mode" "$_file" "$_bid" "$_exists"
  local _action="$_PLAN_ACTION"
  [[ "$_action" != noop && "$_action" != skip && "$_action" != assemble ]] || return 0
  _ss__do_block_action "$_action" "$_file" "$_bid"
}

# --- Line-scope target (BASH_ENV in /etc/environment) --------------------- #
#
# Line targets manage a single unmarked `KEY=value` line rather than a marker
# block, so they need their own apply AND probe logic — the generic block/marker
# path never matches (there is no marker), which would make every fail-mode run
# report a phantom conflict on an existing /etc/environment.

_ss__line_target_pair() {
  # Print "KEY\tVALUE" for a line target's single managed line, via its resolver.
  local _tid="$1"
  local _resolver="${_FEAT_SS_LINE_RESOLVER[$_tid]:-}"
  [[ -n "$_resolver" ]] && declare -f "$_resolver" > /dev/null || return 1
  "$_resolver"
}

_ss__line_block_eligible() {
  # A line target carries exactly one registry block (its option/when carrier);
  # the line is written only when that block passes `when`, precondition, and is
  # enabled — same gating as marker blocks, so e.g.
  # block_sys_environment_bash_env=false is honored.
  local _tid="$1" _bid
  for _bid in ${_FEAT_SS_TARGET_BLOCKS[$_tid]}; do
    [[ -n "$_bid" ]] || continue
    _ss__when_passes "${_FEAT_SS_BLOCK_WHEN[$_bid]:-}" || return 1
    _block_precondition_met "${_FEAT_SS_BLOCK_PRECONDITION[$_bid]:-}" || return 1
    _ss__block_enabled "$_bid" || return 1
    return 0
  done
  return 0
}

_ss__apply_line_target() {
  local _tid="$1" _path="$2" _mode="$3"
  local _pair _key _value _line _cur _eligible=1
  _pair="$(_ss__line_target_pair "$_tid")" || return 0
  _key="${_pair%%$'\t'*}"
  _value="${_pair#*$'\t'}"
  _line="${_key}=${_value}"
  _cur="$(grep -E "^${_key}=" "$_path" 2> /dev/null | tail -n 1 || true)"
  _ss__line_block_eligible "$_tid" || _eligible=0
  case "$_mode" in
    uninstall)
      if [[ -n "$_cur" ]]; then
        grep -v "^${_key}=" "$_path" 2> /dev/null | file__tee "$_path" || true
        logging__success "  Removed ${_key} from ${_path}"
      fi
      ;;
    skip)
      if ((_eligible)) && [[ -z "$_cur" ]]; then
        file__mkdir "$(dirname "$_path")"
        printf '%s\n' "$_line" | file__tee --append "$_path"
        logging__success "  ${_line} → ${_path}"
      fi
      ;;
    reinstall | update | fail)
      if ! ((_eligible)); then
        # Disabled line block: remove an existing managed line (same semantics
        # as a disabled marker block on update).
        if [[ -n "$_cur" ]]; then
          grep -v "^${_key}=" "$_path" 2> /dev/null | file__tee "$_path" || true
          logging__success "  Removed ${_key} from ${_path} (block disabled)"
        fi
      elif [[ -z "$_cur" ]]; then
        file__mkdir "$(dirname "$_path")"
        printf '%s\n' "$_line" | file__tee --append "$_path"
        logging__success "  ${_line} → ${_path}"
      elif [[ "$_cur" != "$_line" ]]; then
        grep -v "^${_key}=" "$_path" 2> /dev/null | file__tee "$_path" || true
        printf '%s\n' "$_line" | file__tee --append "$_path"
        logging__success "  ${_line} → ${_path}"
      fi
      ;;
  esac
}

_ss__probe_line_target() {
  # Conflict iff the file exists and applying would change it: the managed line
  # is present with a different value, or present while its block is disabled
  # (removal is also a write). An absent line/file is not a conflict.
  local _tid="$1" _path="$2"
  local _pair _key _value _line _cur
  _pair="$(_ss__line_target_pair "$_tid")" || return 0
  _key="${_pair%%$'\t'*}"
  _value="${_pair#*$'\t'}"
  _line="${_key}=${_value}"
  _cur="$(grep -E "^${_key}=" "$_path" 2> /dev/null | tail -n 1 || true)"
  [[ -n "$_cur" ]] || return 0
  if ! _ss__line_block_eligible "$_tid"; then
    _SS_CONFLICTS+=("${_tid}|${_path}|managed line would be removed")
  elif [[ "$_cur" != "$_line" ]]; then
    _SS_CONFLICTS+=("${_tid}|${_path}|managed line already set")
  fi
}

# --- Per-target apply / probe --------------------------------------------- #

_ss__resolved_backup_root() {
  # Resolve the backup root from the backup_dir option's ordered candidates
  # (first writable wins; same pattern as setup-files). Cached after first call.
  if [[ -z "${_SS_BACKUP_ROOT:-}" ]]; then
    local -a _bd_args=()
    local _p
    while IFS= read -r _p; do
      [[ -n "$_p" ]] && _bd_args+=("$(users__expand_path "$_p" 2> /dev/null || printf '%s' "$_p")")
    done <<< "${BACKUP_DIR:-}"
    if ((${#_bd_args[@]})); then
      _SS_BACKUP_ROOT="$(users__first_writeable_path -- "${_bd_args[@]}" 2> /dev/null)" || {
        logging__error "setup-shell: no configured backup_dir candidate is writable."
        return 1
      }
    else
      _SS_BACKUP_ROOT="${_FEAT_SHARE_DIR_ROOT}/backups"
    fi
  fi
  printf '%s' "${_SS_BACKUP_ROOT}"
}

_ss__backup_dir_for_scope() {
  # Backup directory for a target scope: system/skel → the resolved backup_dir
  # root; user → the target user's own share dir (per-user isolation, so one
  # user's backed-up dotfiles don't land in another user's or root's dir).
  local _scope="$1"
  case "$_scope" in
    user)
      local _dir
      _dir="$(users__nonroot_share_dir "${_SS_USER}" 2> /dev/null || true)"
      if [[ -n "$_dir" ]]; then
        printf '%s/backups' "$_dir"
      else
        _ss__resolved_backup_root
      fi
      ;;
    *) _ss__resolved_backup_root ;;
  esac
}

_ss__apply_target() {
  local _tid="$1" _path="$2" _mode="$3"
  local _scope="${_FEAT_SS_TARGET_SCOPE[$_tid]}"
  [[ -n "$_path" ]] || return 0

  if [[ "$_scope" == line ]]; then
    _ss__apply_line_target "$_tid" "$_path" "$_mode"
    return 0
  fi

  local _exists=false
  [[ -f "$_path" ]] && _exists=true

  # Whole-file assembly: reinstall always; skip/update/fail only when absent.
  if [[ "$_mode" == reinstall ]] ||
    { [[ "$_mode" == skip || "$_mode" == update || "$_mode" == fail ]] && [[ "$_exists" != true ]]; }; then
    local _assembled
    _assembled="$(_ss__assemble_target "$_tid")"
    if [[ -n "$_assembled" ]]; then
      # Carry over + back up foreign managed blocks before the destructive
      # reinstall replace. Only reinstall-on-existing reaches this: skip/update/
      # fail assemble solely when the file is absent (nothing to preserve).
      local _preserved=""
      if [[ "$_mode" == reinstall && "$_exists" == true ]]; then
        local _backup_dir
        _backup_dir="$(_ss__backup_dir_for_scope "$_scope")" || return 1
        file__backup_if_policy "$_path" "${BACKUP:-auto}" "$_backup_dir" > /dev/null || return 1
        _preserved="$(_ss__collect_preserved_blocks "$_path")"
      fi
      file__mkdir "$(dirname "$_path")"
      # $(...) strips the assembler's trailing newlines; restore the end-marker
      # terminator plus the blank line so assembled files end exactly like
      # marker blocks appended to existing files do. Preserved foreign blocks (if
      # any) follow, separated by a blank line, each already marker-wrapped.
      if [[ -n "$_preserved" ]]; then
        printf '%s\n\n%s\n' "$_assembled" "$_preserved" | file__tee "$_path"
        logging__info "  Preserved foreign managed block(s) across reinstall of ${_path}."
      else
        printf '%s\n\n' "$_assembled" | file__tee "$_path"
      fi
      file__chmod 644 "$_path" 2> /dev/null || true
      logging__success "  ${_path} (assembled)"
    fi
    return 0
  fi

  # skip on an existing file: strict no-op.
  if [[ "$_mode" == skip ]]; then
    logging__debug "  Skipping existing ${_path} (mode=skip)."
    return 0
  fi

  # uninstall: strip every block's marker, then delete iff whitespace-only.
  if [[ "$_mode" == uninstall ]]; then
    [[ "$_exists" == true ]] || return 0
    local _bid
    for _bid in ${_FEAT_SS_TARGET_BLOCKS[$_tid]}; do
      [[ -n "$_bid" ]] || continue
      _ss__apply_block uninstall "$_path" "$_bid" "$_exists"
    done
    if [[ -f "$_path" ]] && _ss__file_whitespace_only "$_path"; then
      file__rm "$_path"
      logging__success "  Removed empty ${_path}"
    else
      logging__success "  Stripped markers from ${_path}"
    fi
    return 0
  fi

  # update / fail on an existing file: per-block inject/sync/remove.
  #
  # Ordering of first-time injects ("insert bottom-up"): when the
  # after-interactivity-guard-or-eof anchor MATCHES an interior guard, each
  # insert lands at the same fixed line (pushing earlier inserts down), so those
  # blocks are deferred and applied in REVERSE registry order — the final file
  # order then matches the registry. When the anchor falls back to EOF (no
  # guard, e.g. stock Debian bashrc), inserts append below one another, so
  # forward order is already correct. file-top and plain eof injects stack
  # forward as well; sync/remove are order-insensitive.
  local _bid _anchor _line _total
  local -a _deferred_injects=()
  for _bid in ${_FEAT_SS_TARGET_BLOCKS[$_tid]}; do
    [[ -n "$_bid" ]] || continue
    _ss__target_plan_block "$_mode" "$_path" "$_bid" "$_exists"
    if [[ "$_PLAN_ACTION" == inject ]]; then
      _anchor="${_FEAT_SS_BLOCK_ANCHOR[$_bid]:-}"
      if [[ "$_anchor" == after-interactivity-guard-or-eof ]]; then
        _line="$(shell__resolve_inject_line_v1 --file "$_path" --anchor "$_anchor")"
        _total="$(wc -l < "$_path")"
        if ((_line <= _total)); then
          _deferred_injects+=("$_bid")
          continue
        fi
      fi
    fi
    [[ "$_PLAN_ACTION" != noop && "$_PLAN_ACTION" != skip && "$_PLAN_ACTION" != assemble ]] || continue
    _ss__do_block_action "$_PLAN_ACTION" "$_path" "$_bid"
  done
  local _i
  for ((_i = ${#_deferred_injects[@]} - 1; _i >= 0; _i--)); do
    _ss__do_block_action inject "$_path" "${_deferred_injects[$_i]}"
  done
  logging__success "  ${_path}"
}

_ss__probe_target() {
  # Collect fail-mode conflicts for one target. Only targets whose own mode is
  # `fail` are probed. Absent targets never conflict.
  local _tid="$1" _path="$2" _mode="$3"
  [[ "$_mode" == fail ]] || return 0
  [[ -n "$_path" ]] || return 0
  local _scope="${_FEAT_SS_TARGET_SCOPE[$_tid]}"
  if [[ "$_scope" == line ]]; then
    _ss__probe_line_target "$_tid" "$_path"
    return 0
  fi
  local _exists=false
  [[ -f "$_path" ]] && _exists=true
  [[ "$_exists" == true ]] || return 0
  # One conflict entry per target (not per block): a target conflicts if any of
  # its blocks would write to the existing file.
  local _bid
  for _bid in ${_FEAT_SS_TARGET_BLOCKS[$_tid]}; do
    [[ -n "$_bid" ]] || continue
    _ss__target_plan_block fail "$_path" "$_bid" "$_exists"
    if [[ "$_PLAN_WOULD_WRITE" == true ]]; then
      _SS_CONFLICTS+=("${_tid}|${_path}|would modify existing file")
      return 0
    fi
  done
}

_ss__report_fail_conflicts() {
  local _n="${#_SS_CONFLICTS[@]}"
  ((_n)) || return 0
  logging__error "if_exists=fail: refusing to install; ${_n} existing target(s) would be modified:"
  local _c _tid _path _reason
  for _c in "${_SS_CONFLICTS[@]}"; do
    IFS='|' read -r _tid _path _reason <<< "$_c"
    logging__error "  [${_tid}] ${_path} (${_reason})"
  done
  logging__fatal "Exiting with status 1 (if_exists=fail)."
  return 1
}

# --- Path resolution for system/skel targets ------------------------------ #

_ss__resolve_target_path() {
  # Resolve a system/skel target's deploy path: path_resolver fn > deploy_option
  # value (or its default) > default_path.
  local _tid="$1"
  local _resolver="${_FEAT_SS_TARGET_PATH_RESOLVER[$_tid]:-}"
  local _deploy="${_FEAT_SS_TARGET_DEPLOY_OPTION[$_tid]:-}"
  local _default="${_FEAT_SS_TARGET_DEFAULT_PATH[$_tid]:-}"
  if [[ -n "$_resolver" ]] && declare -f "$_resolver" > /dev/null; then
    "$_resolver"
  elif [[ -n "$_deploy" ]]; then
    _ss__resolve_sys_path "$_deploy" "$_default"
  else
    printf '%s' "$_default"
  fi
}

# --- Passes: system + skel (line included) -------------------------------- #

_ss__each_sys_skel_target() {
  # Iterate system/skel/line targets in registry order, invoking a callback with
  # (tid, path, mode). User-scope targets are handled per-user in install.bash.
  local _cb="$1"
  local _tid _scope _when _deploy _path _mode
  for _tid in "${_FEAT_SS_TARGET_ORDER[@]}"; do
    _scope="${_FEAT_SS_TARGET_SCOPE[$_tid]}"
    [[ "$_scope" == user ]] && continue
    _when="${_FEAT_SS_TARGET_WHEN[$_tid]:-}"
    _ss__when_passes "$_when" || continue
    _deploy="${_FEAT_SS_TARGET_DEPLOY_OPTION[$_tid]:-}"
    if [[ -n "$_deploy" ]] && _ss__deploy_path_empty "$_deploy"; then
      logging__debug "Skipping target ${_tid}: deploy path option empty."
      continue
    fi
    # `|| continue` also absorbs resolver failures (e.g. a skel resolver
    # declining an absolute user path) — without it, set -e aborts the install.
    _path="$(_ss__resolve_target_path "$_tid")" || continue
    [[ -n "$_path" ]] || continue
    _mode="$(_ss__target_mode_for "$_scope")"
    "$_cb" "$_tid" "$_path" "$_mode" || return $?
  done
}

_ss__apply_pass() {
  _ss__each_sys_skel_target _ss__apply_target
}

_ss__probe_pass() {
  # Collect-only: resets the conflict list and probes system/skel/line targets
  # when either of those scopes is fail. The caller runs the user-scope probe
  # next and then reports all collected conflicts in one _ss__report_fail_conflicts
  # call, so conflicts from every fail-scoped scope appear in a single message.
  _SS_CONFLICTS=()
  [[ "${IF_EXISTS_SYS}" == fail || "${IF_EXISTS_SKEL}" == fail ]] || return 0
  _ss__each_sys_skel_target _ss__probe_target
}
