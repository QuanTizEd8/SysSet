# shellcheck shell=bash
#
# setup-files: declaratively manage files, directories, symlinks, and
# marker-delimited content blocks via a YAML/JSON manifest.
#
# Uses the self-copy pattern (__deploy_self__, shared in install.tmpl.bash) so
# lifecycle hook scripts and the entrypoint — which run long after the build
# tarball is gone — can call back into a full copy of this feature with
# complete DevFeats lib access. See __install_run__ / __install_finish_post.

# ============================================================================
# Hooks
# ============================================================================

__if_exists_dispatch__() {
  # Per the URD, every if_exists value except 'uninstall' applies the
  # manifest(s) normally — the shared skip/fail/reinstall/update semantics
  # don't apply to a declarative file-state feature.
  case "${IF_EXISTS}" in
    uninstall) __uninstall__ ;;
    *) __install__ ;;
  esac
}

__install_run__() {
  # Deploy self to a persistent share dir (no-op if already deployed) so
  # lifecycle scripts can call back into a full copy of this feature later.
  __deploy_self__

  # Resolve the user list once; used by _apply_config for user-scoped entries.
  local -a _ul_args=()
  local _u
  while IFS= read -r _u; do [[ -n "$_u" ]] && _ul_args+=(--user "$_u"); done <<< "${ADD_USERS:-}"
  mapfile -t _SF_USERS < <(users__resolve_list \
    --current "$ADD_CURRENT_USER" \
    --remote "$ADD_REMOTE_USER" \
    --container "$ADD_CONTAINER_USER" \
    "${_ul_args[@]}")

  # Resolve the backup directory (first writable candidate). Candidates may
  # contain ${HOME}/~ — expand before the writability check.
  local -a _bd_args=()
  local _p
  while IFS= read -r _p; do
    [[ -n "$_p" ]] && _bd_args+=("$(users__expand_path "$_p" 2> /dev/null || printf '%s' "$_p")")
  done <<< "${BACKUP_DIR:-}"
  _SF_BACKUP_DIR="$(users__first_writeable_path -- "${_bd_args[@]}" 2> /dev/null || true)"

  # Persist materialized lifecycle manifests to the share dir. _content_or_uri
  # already resolved each MANIFEST_* to a local file (or left it as a
  # not-yet-existing path/URI, when allow_nonexistent applied). Session temp
  # files must be copied to persistent storage before this script exits.
  _sf_persist_manifest MANIFEST_ON_CREATE on_create
  _sf_persist_manifest MANIFEST_UPDATE_CONTENT update_content
  _sf_persist_manifest MANIFEST_POST_CREATE post_create
  _sf_persist_manifest MANIFEST_ENTRYPOINT entrypoint
  _sf_persist_manifest MANIFEST_POST_START post_start
  _sf_persist_manifest MANIFEST_POST_ATTACH post_attach

  # Apply the build-time manifest (already resolved to a local file).
  if [[ -n "$MANIFEST" ]]; then
    _apply_config "$MANIFEST"
  else
    logging__skip "No build-time manifest set; skipping immediate apply."
  fi
}

__install_finish_post() {
  # Write a lifecycle script + .conf file for each non-empty MANIFEST_* option.
  # At lifecycle time only the stage being applied is non-empty, so this loop
  # iterates zero times there — scripts are not re-written on every hook run.
  local _installer="${_FEAT_SHARE_DIR_ROOT}/install.sh"

  local _script_body
  _script_body=$(
    cat << 'EOF'
#!/bin/sh
set -e
_d="$(cd "$(dirname "$0")" && pwd)"
. "${_d}/$(basename "$0" .sh).conf"
set -- --manifest "$MANIFEST" \
  --add_current_user "$ADD_CURRENT_USER" \
  --add_remote_user "$ADD_REMOTE_USER" \
  --add_container_user "$ADD_CONTAINER_USER"
[ -n "${BACKUP:-}" ] && set -- "$@" --backup "$BACKUP"
[ -n "${ADD_USERS:-}" ] && set -- "$@" --add_users "$ADD_USERS"
exec sh "$INSTALLER" "$@"
EOF
  )

  local -A _stage_map=(
    [MANIFEST_ON_CREATE]="${_FEAT_LIFECYCLE_ON_CREATE}setup.sh"
    [MANIFEST_UPDATE_CONTENT]="${_FEAT_LIFECYCLE_UPDATE_CONTENT}setup.sh"
    [MANIFEST_POST_CREATE]="${_FEAT_LIFECYCLE_POST_CREATE}setup.sh"
    [MANIFEST_POST_START]="${_FEAT_LIFECYCLE_POST_START}setup.sh"
    [MANIFEST_POST_ATTACH]="${_FEAT_LIFECYCLE_POST_ATTACH}setup.sh"
    [MANIFEST_ENTRYPOINT]="${_FEAT_ENTRYPOINT_PATH}"
  )

  local _opt_var
  for _opt_var in "${!_stage_map[@]}"; do
    local _value="${!_opt_var:-}"
    [[ -z "$_value" ]] && continue

    local _dest="${_stage_map[$_opt_var]}"
    file__mkdir "$(dirname "$_dest")"
    printf '%s\n' "$_script_body" | file__tee "$_dest"
    file__chmod +x "$_dest"

    # .conf file: POSIX-sh-safe single-quoted values (posix__quote). No
    # fetch_headers/fetch_netrc: manifests are already local files at this
    # point (inline content materialized, remote URIs already fetched) — no
    # auth is needed to read them again at lifecycle time.
    {
      printf 'INSTALLER=%s\n' "$(posix__quote "$_installer")"
      printf 'MANIFEST=%s\n' "$(posix__quote "$_value")"
      printf 'ADD_CURRENT_USER=%s\n' "$(posix__quote "$ADD_CURRENT_USER")"
      printf 'ADD_REMOTE_USER=%s\n' "$(posix__quote "$ADD_REMOTE_USER")"
      printf 'ADD_CONTAINER_USER=%s\n' "$(posix__quote "$ADD_CONTAINER_USER")"
      # `|| true` on the LAST statement of this group: since the group's own
      # exit status feeds a pipeline under `pipefail`, a false guard here
      # (e.g. ADD_USERS unset) would otherwise make the whole pipeline "fail"
      # and abort the script under `set -e` — even though nothing went wrong.
      [[ -n "${ADD_USERS:-}" ]] && printf 'ADD_USERS=%s\n' "$(posix__quote "$ADD_USERS")"
      [[ -n "${BACKUP:-}" ]] && printf 'BACKUP=%s\n' "$(posix__quote "$BACKUP")"
      true
    } | file__tee "${_dest%.sh}.conf"

    logging__success "Registered lifecycle script: $(basename "$_dest")"
  done
}

__uninstall_run__() {
  local -a _ul_args=()
  local _u
  while IFS= read -r _u; do [[ -n "$_u" ]] && _ul_args+=(--user "$_u"); done <<< "${ADD_USERS:-}"
  mapfile -t _SF_USERS < <(users__resolve_list \
    --current "$ADD_CURRENT_USER" \
    --remote "$ADD_REMOTE_USER" \
    --container "$ADD_CONTAINER_USER" \
    "${_ul_args[@]}")

  local -a _bd_args=()
  local _p
  while IFS= read -r _p; do
    [[ -n "$_p" ]] && _bd_args+=("$(users__expand_path "$_p" 2> /dev/null || printf '%s' "$_p")")
  done <<< "${BACKUP_DIR:-}"
  _SF_BACKUP_DIR="$(users__first_writeable_path -- "${_bd_args[@]}" 2> /dev/null || true)"

  _do_uninstall

  file__rm -rf "${_FEAT_SHARE_DIR_ROOT}"
}

# ============================================================================
# Manifest persistence
# ============================================================================

_sf_persist_manifest() {
  # _content_or_uri materializes inline content and fetched URIs to
  # SESSION temp files (deleted when the build script exits). For lifecycle
  # hooks, the materialized content must be copied to a PERSISTENT location
  # before the session ends. A URI or not-yet-existing local path is left
  # as-is, for re-resolution at lifecycle invocation time.
  local _var_name="$1" _stage="$2"
  local _val="${!_var_name:-}"
  [[ -z "$_val" ]] && return 0

  if [[ -f "$_val" ]]; then
    local _dest="${_FEAT_SHARE_DIR_ROOT}/manifests/${_stage}.yaml"
    file__mkdir "$(dirname "$_dest")"
    file__cp "$_val" "$_dest"
    printf -v "$_var_name" '%s' "$_dest"
  fi
}

# ============================================================================
# Config processing
# ============================================================================

_sf_is_user_scoped() {
  local _dest="$1"
  # Matching the literal, unexpanded "~/" / "${HOME}/" prefix is intentional:
  # this runs on the RAW dest before per-user expansion (see _apply_config).
  # shellcheck disable=SC2088,SC2016
  [[ "$_dest" == "~/"* || "$_dest" == '${HOME}/'* ]]
}

# _sf_strict_check <expanded> <entry> <raw> — enforce strict_vars.
#
# MUST inspect <raw> (the PRE-expansion text), not <expanded>: bash's own
# ${VAR} parameter expansion silently resolves an undefined variable to an
# empty string during expansion (standard behavior, not an error), so by the
# time the string is expanded there is no longer anything in it to detect —
# an undefined reference and a defined-but-empty one become indistinguishable
# in the OUTPUT. Detection therefore has to happen on the ORIGINAL text,
# by extracting each bare ${VAR} reference (no ${VAR:-default}/${VAR:+alt}
# fallback — those forms always resolve to something, so they are never
# "undefined" in the relevant sense) and checking whether that name is
# actually set, in THIS process's environment. This covers the common case
# correctly: `vars:` block entries are exported into this process (and also
# forwarded to any per-user login shell via --env), so a reference to a
# custom var or a real ambient env var is checked accurately; a variable
# that only happens to differ in a per-user login shell's own profile is a
# known, accepted edge case this check does not see.
_sf_strict_check() {
  local _expanded="$1" _entry="$2" _raw="${3:-}"
  local _strict
  # NOT `.strict_vars // "true"`: jq's `//` treats JSON `false` as falsy (same
  # as null), so that idiom would silently coerce an explicit `false` back to
  # "true" — exactly the boolean this check exists to honour. `== null` only
  # matches a genuinely absent field.
  _strict="$(json__query -r 'if .strict_vars == null then "true" else (.strict_vars | tostring) end' <<< "$_entry")"
  if [[ "$_strict" == "true" && -n "$_raw" ]]; then
    local _ref _name
    while IFS= read -r _ref; do
      [[ -z "$_ref" ]] && continue
      _name="${_ref#\$\{}"
      _name="${_name%\}}"
      [[ -v "$_name" ]] && continue
      logging__error "Undefined variable: ${_ref} (set strict_vars:false to suppress)"
      return 1
    done < <(printf '%s' "$_raw" | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}')
  fi
  printf '%s' "$_expanded"
}

# _sf_expand_path <raw> <entry> [<user>] — strict expander for `dest` ONLY.
# Delegates to users__expand_path (rejects command-injection metacharacters —
# appropriate since dest becomes a direct filesystem write target).
_sf_expand_path() {
  local _s="$1" _entry="$2" _user="${3:-}"
  local _result
  _result="$(users__expand_path "${_SF_VAR_ENV_ARGS[@]}" ${_user:+--user "$_user"} "$_s")" || {
    logging__error "Path expansion failed: ${_s}"
    return 1
  }
  _sf_strict_check "$_result" "$_entry" "$_s"
}

# _sf_expand_content <raw> <entry> [<user>] — relaxed expander for everything
# EXCEPT dest (src, anchor, marker match/text, inline content). Command
# substitution is neutralized rather than rejecting the whole input, so ERE
# regex (which commonly uses parens/pipes) and URIs (which commonly use
# &/; in query strings) pass through unaffected.
_sf_expand_content() {
  local _s="$1" _entry="$2" _user="${3:-}"
  local _result
  _result="$(users__expand_string "${_SF_VAR_ENV_ARGS[@]}" ${_user:+--user "$_user"} "$_s")" || {
    logging__error "Content expansion failed."
    return 1
  }
  _sf_strict_check "$_result" "$_entry" "$_s"
}

# Prints one --header/--netrc-file arg per line for uri__fetch_asset.
# Entry-level fetch_headers/fetch_netrc win; feature-level FETCH_HEADERS/
# FETCH_NETRC are the fallback (meaningful only at build time — those options
# are never propagated to lifecycle scripts).
_sf_build_fetch_args() {
  local _entry="$1" _user="$2"
  local _has_entry_headers
  _has_entry_headers="$(json__query -r 'has("fetch_headers")' <<< "$_entry")"
  if [[ "$_has_entry_headers" == "true" ]]; then
    local _h
    while IFS= read -r _h; do
      [[ -z "$_h" ]] && continue
      _h="$(_sf_expand_content "$_h" "$_entry" "$_user")" || continue
      printf -- '--header\n%s\n' "$_h"
    done < <(json__query -r '.fetch_headers[]' <<< "$_entry")
  else
    local _h
    while IFS= read -r _h; do
      [[ -n "$_h" ]] && printf -- '--header\n%s\n' "$_h"
    done <<< "${FETCH_HEADERS:-}"
  fi

  local _netrc
  _netrc="$(json__query -r '.fetch_netrc // ""' <<< "$_entry")"
  if [[ -n "$_netrc" ]]; then
    _netrc="$(_sf_expand_content "$_netrc" "$_entry" "$_user")" && printf -- '--netrc-file\n%s\n' "$_netrc"
  elif [[ -n "${FETCH_NETRC:-}" ]]; then
    printf -- '--netrc-file\n%s\n' "$FETCH_NETRC"
  fi
}

_apply_config() {
  # The manifest is already a local file, resolved by _content_or_uri and
  # validated against the JSON Schema by _jsonschema during __init_args__.
  local _config="$1"
  local _json_config
  _json_config="$(json__from_yaml "$_config")"

  # Custom vars: exported in-process (covers system-scoped entries, which
  # dispatch in-process) AND threaded through _SF_VAR_ENV_ARGS as --env flags
  # (covers user-scoped entries, which expand fields inside a fresh `su -l`
  # login shell that does NOT inherit this process's exported vars).
  local _vars_json
  _vars_json="$(json__query -r '.vars // {}' <<< "$_json_config")"
  local -a _var_names=()
  _SF_VAR_ENV_ARGS=()
  local _kv
  while IFS= read -r _kv; do
    local _k="${_kv%%=*}" _v="${_kv#*=}"
    [[ -z "$_k" ]] && continue
    export "$_k"="$_v"
    _var_names+=("$_k")
    _SF_VAR_ENV_ARGS+=(--env "${_k}=${_v}")
  done < <(json__query -r 'to_entries[] | "\(.key)=\(.value)"' <<< "$_vars_json")

  local _defaults_json
  _defaults_json="$(json__query '.defaults // {}' <<< "$_json_config")"
  local _entries_json
  _entries_json="$(json__query '.files // []' <<< "$_json_config")"
  local _any_op_failed=0

  # Merge entries with defaults, then stream as one-JSON-object-per-line
  # (NDJSON) so the main loop reads entries via a plain `while read` instead
  # of re-parsing and re-indexing into the WHOLE array on every iteration
  # (O(n^2) for n entries). Full schema validation already ran during
  # __init_args__ via _jsonschema — no separate pass needed here.
  local _merged_ndjson
  # shellcheck disable=SC2016
  _merged_ndjson="$(json__query -c --argjson d "$_defaults_json" '.[] | $d * .' <<< "$_entries_json")"

  local _i=-1 _entry
  while IFS= read -r _entry; do
    [[ -z "$_entry" ]] && continue
    # `(( expr ))` returns exit status 1 whenever expr evaluates to 0, and
    # post-increment `_i++` evaluates to the PRE-increment value — so the
    # moment _i is 0 (the second entry), `((_i++))` alone would return 1 and
    # kill the whole script under `set -e`. The `|| true` guard matches the
    # same fix already used for __dep_install_option_bound__'s _trigger_rows.
    ((_i++)) || true
    local -a _f
    mapfile -d '' -t _f < <(json__query_multi "$_entry" \
      '.op' '.dest // ""' '.on_error // "abort"')
    local _op="${_f[0]}" _raw_dest="${_f[1]}" _on_error="${_f[2]}"

    # Scope detection MUST run on the RAW (unexpanded) dest — expanding first
    # would resolve ${HOME}/~ to the current process's home, destroying the
    # literal prefix this check looks for and misclassifying every
    # user-scoped entry as system-scoped.
    if _sf_is_user_scoped "$_raw_dest"; then
      local -a _user_list
      mapfile -t _user_list < <(json__string_or_array_lines "$_entry" users)
      [[ ${#_user_list[@]} -eq 0 ]] && _user_list=("${_SF_USERS[@]}")

      local -a _expanded_user_list=()
      local _lu
      for _lu in "${_user_list[@]}"; do
        if [[ "$_lu" == "all" ]]; then
          # --current/--remote/--container explicitly disabled: "all" means
          # every regular, interactive-shell user and nothing else — it must
          # not ALSO pull in the current/remote/container user a second time
          # via those flags' own (default-true) inclusion logic, which would
          # incorrectly add root when the installer itself is running as root.
          local -a _all_users
          mapfile -t _all_users < <(users__resolve_list --current false --remote false --container false --all)
          _expanded_user_list+=("${_all_users[@]}")
        else
          _expanded_user_list+=("$_lu")
        fi
      done

      local _user _any_user_failed=0
      for _user in "${_expanded_user_list[@]}"; do
        [[ -z "$_user" ]] && continue
        local _home
        _home="$(users__resolve_home "$_user")"
        if [[ -z "$_home" ]]; then
          logging__warn "Cannot resolve home for '${_user}'; skipping."
          continue
        fi
        local _user_dest
        _user_dest="$(_sf_expand_path "$_raw_dest" "$_entry" "$_user")" || continue
        local _rc=0
        (
          export HOME="$_home" USERNAME="$_user"
          _dispatch_op "$_op" "$_user_dest" "$_entry" "$_user"
        ) || _rc=$?
        if [[ $_rc -ne 0 ]]; then
          case "$_on_error" in
            abort)
              [[ ${#_var_names[@]} -gt 0 ]] && unset "${_var_names[@]}"
              return 1
              ;;
            abort-entry)
              _any_user_failed=1
              break
              ;;
            continue)
              logging__warn "Entry ${_i} failed for user '${_user}' (on_error:continue)."
              _any_user_failed=1
              ;;
            ignore) : ;;
          esac
        fi
      done
      [[ $_any_user_failed -ne 0 && "$_on_error" != "ignore" ]] && _any_op_failed=1
    else
      # System-scoped: must be absolute (not a bare relative path).
      if [[ "$_raw_dest" != /* ]]; then
        logging__error "Entry ${_i}: dest '${_raw_dest}' is a bare relative path; use an absolute path, or ~/... / \${HOME}/... for a user-scoped entry."
        case "$_on_error" in
          abort)
            [[ ${#_var_names[@]} -gt 0 ]] && unset "${_var_names[@]}"
            return 1
            ;;
          ignore) : ;;
          *) _any_op_failed=1 ;;
        esac
        continue
      fi
      # `users` is not meaningful on a system-scoped dest — reject rather
      # than silently ignore (it would run once, not per-user).
      if [[ "$(json__query -r 'has("users")' <<< "$_entry")" == "true" ]]; then
        logging__error "Entry ${_i}: 'users' field is not allowed on system-scoped dest '${_raw_dest}'."
        case "$_on_error" in
          abort)
            [[ ${#_var_names[@]} -gt 0 ]] && unset "${_var_names[@]}"
            return 1
            ;;
          ignore) : ;;
          *) _any_op_failed=1 ;;
        esac
        continue
      fi

      local _dest
      _dest="$(_sf_expand_path "$_raw_dest" "$_entry")" || continue
      local _rc=0
      _dispatch_op "$_op" "$_dest" "$_entry" "" || _rc=$?
      if [[ $_rc -ne 0 ]]; then
        case "$_on_error" in
          abort)
            [[ ${#_var_names[@]} -gt 0 ]] && unset "${_var_names[@]}"
            return 1
            ;;
          abort-entry | continue)
            logging__warn "Entry ${_i} failed (on_error:${_on_error})."
            _any_op_failed=1
            ;;
          ignore) : ;;
        esac
      fi
    fi
  done <<< "$_merged_ndjson"

  [[ ${#_var_names[@]} -gt 0 ]] && unset "${_var_names[@]}"
  [[ ${_any_op_failed:-0} -eq 0 ]]
}

_dispatch_op() {
  local _op="$1" _dest="$2" _entry="$3" _user="$4"
  case "$_op" in
    create) _op_create "$_dest" "$_entry" "$_user" ;;
    inject) _op_inject "$_dest" "$_entry" "$_user" ;;
    delete) _op_delete "$_dest" "$_entry" "$_user" ;;
    symlink) _op_symlink "$_dest" "$_entry" "$_user" ;;
    mkdir) _op_mkdir "$_dest" "$_entry" "$_user" ;;
    chmod) _op_chmod "$_dest" "$_entry" "$_user" ;;
    move) _op_move "$_dest" "$_entry" "$_user" ;;
    touch) _op_touch "$_dest" "$_entry" "$_user" ;;
    *)
      logging__error "Unknown op '${_op}'."
      return 1
      ;;
  esac
}

# ============================================================================
# State management
# ============================================================================

_sf_state_file() {
  local _user="$1"
  if [[ -n "$_user" ]]; then
    printf '%s/state.json' "$(users__nonroot_share_dir "$_user")"
  else
    printf '%s/state.json' "${_FEAT_SHARE_DIR_ROOT}"
  fi
}

_sf_state_read() {
  local _state_file="$1"
  [[ -f "$_state_file" ]] && cat "$_state_file" || printf '{"entries":[]}'
}

_sf_state_upsert() {
  # Keyed by (op, dest), NOT dest alone: a single dest commonly goes through
  # several DIFFERENT ops in one manifest (e.g. create, then inject, then
  # chmod, all on the same file) — each needs its own tracked entry so
  # uninstall can reverse all of them. Keying by dest alone would collapse
  # them into one record, silently losing the create/inject history. Keying
  # by (op, dest) still gives idempotent re-application its intended effect:
  # re-running the SAME op against the SAME dest (e.g. a lifecycle hook that
  # re-applies the same manifest on every container start) updates the
  # existing entry in place rather than accumulating duplicates, preserving
  # the true original_hash/original_perms/timestamp_first from the first run.
  local _state_file="$1" _new_entry="$2"
  local _tmp
  _tmp="$(file__mktmpdir sf-state)/state.json"
  # shellcheck disable=SC2016
  _sf_state_read "$_state_file" | json__query --argjson e "$_new_entry" '
    .entries |= (
      if any(.dest == $e.dest and .op == $e.op)
      then map(if .dest == $e.dest and .op == $e.op then
        . as $old | $e
        | .original_hash  = ($old.original_hash  // $e.original_hash)
        | .original_perms = ($old.original_perms // $e.original_perms)
        | .timestamp_first = ($old.timestamp_first // $e.timestamp_first)
      else . end)
      else . + [$e]
      end
    )' > "$_tmp"
  local _state_dir
  _state_dir="$(dirname "$_state_file")"
  file__mkdir "$_state_dir"
  file__mv "$_tmp" "$_state_file"
}

_sf_hash() {
  [[ -f "$1" ]] && verify__hash_file "$1" || printf 'null'
}

# entry_backup: the entry's own .backup value ("" when unset, falling back to
# the global $BACKUP feature option).
_sf_maybe_backup() {
  local _dest="$1" _entry_backup="${2:-}"
  file__backup_if_policy "$_dest" "${_entry_backup:-$BACKUP}" "${_SF_BACKUP_DIR:-}"
}

# _sf_apply_attrs <dest> <entry> — read chmod/owner/group from entry, apply to
# dest if set. Used by create/inject/touch (the single-path, no-special-
# casing ops). mkdir has its own inline version (loops over newly-created
# intermediate dirs for recursive_attrs); chmod has its own (captures
# original_perms BEFORE applying); symlink has its own (chmod deliberately
# NOT applied — see _op_symlink).
_sf_apply_attrs() {
  local _dest="$1" _entry="$2"
  local -a _f
  mapfile -d '' -t _f < <(json__query_multi "$_entry" '.chmod // ""' '.owner // ""' '.group // ""')
  [[ -n "${_f[0]}" ]] && file__chmod "${_f[0]}" "$_dest"
  [[ -n "${_f[1]}" || -n "${_f[2]}" ]] && file__chown "${_f[1]}:${_f[2]}" "$_dest"
}

# _sf_record_state <user> <op> <dest> <created:true|false> [<original_hash>] \
#                  [<original_perms>] [<current_hash>] [<backup_path>] [<extra_json>]
# Builds the canonical state entry shape and upserts it. Empty string for any
# of original_hash/original_perms/current_hash/backup_path means null.
# extra_json (default '{}') is merged in for op-specific fields (inject's
# begin_marker/end_marker, move's src).
_sf_record_state() {
  local _user="$1" _op="$2" _dest="$3" _created="$4"
  local _orig_hash="${5:-}" _orig_perms="${6:-}" _cur_hash="${7:-}" _backup_path="${8:-}" _extra="${9:-{\}}"
  local _ts
  _ts="$(date -u +%FT%TZ)"
  local _base
  # shellcheck disable=SC2016
  _base="$(json__query -n \
    --arg op "$_op" --arg dest "$_dest" --argjson created "$_created" \
    --arg oh "$_orig_hash" --arg opm "$_orig_perms" --arg ch "$_cur_hash" --arg bp "$_backup_path" --arg ts "$_ts" \
    '{op:$op, dest:$dest, created:$created,
      original_hash:  ($oh  | if .=="" then null else . end),
      original_perms: ($opm | if .=="" then null else . end),
      current_hash:   ($ch  | if .=="" then null else . end),
      backup_path:    ($bp  | if .=="" then null else . end),
      timestamp_first:$ts, timestamp_last:$ts}')"
  local _merged
  # shellcheck disable=SC2016
  _merged="$(json__query --argjson e "$_extra" '. * $e' <<< "$_base")"
  _sf_state_upsert "$(_sf_state_file "$_user")" "$_merged"
}

# ============================================================================
# Operations
# ============================================================================

_op_create() {
  local _dest="$1" _entry="$2" _user="$3"

  local -a _f
  mapfile -d '' -t _f < <(json__query_multi "$_entry" \
    '.src // ""' '.content // ""' '.if_exists // "skip"' \
    'if .preserve_perms == null then "false" else (.preserve_perms|tostring) end' '.backup // ""')
  local _src="${_f[0]}" _content="${_f[1]}" _if_exists="${_f[2]}" \
    _preserve_perms="${_f[3]}" _backup_val="${_f[4]}" _bp=""

  local -a _exp
  mapfile -d '' -t _exp < <(users__expand_multi "${_SF_VAR_ENV_ARGS[@]}" ${_user:+--user "$_user"} -- "$_src" "$_content")
  local _raw_src="$_src" _raw_content="$_content"
  _src="$(_sf_strict_check "${_exp[0]}" "$_entry" "$_raw_src")" || return 1
  _content="$(_sf_strict_check "${_exp[1]}" "$_entry" "$_raw_content")" || return 1

  # Directory-tree copy dispatches BEFORE the dest-exists check below:
  # if_exists applies PER-FILE inside the tree (via nested _op_create calls),
  # NOT to $dest as a whole — dest is almost always a pre-existing directory
  # (e.g. dest: ${HOME}), so checking it here would abort the entire copy.
  if [[ -n "$_src" && -d "$_src" ]]; then
    _op_create_tree "$_dest" "$_src" "$_entry" "$_user"
    return
  fi

  if [[ -e "$_dest" ]]; then
    case "$_if_exists" in
      skip)
        logging__skip "${_dest} already exists; skipping."
        return 0
        ;;
      fail)
        logging__error "${_dest} already exists (if_exists:fail)."
        return 1
        ;;
      overwrite) _bp="$(_sf_maybe_backup "$_dest" "$_backup_val")" ;;
    esac
  fi

  local _orig_hash
  _orig_hash="$(_sf_hash "$_dest")"
  local _created=false
  [[ ! -e "$_dest" ]] && _created=true

  if [[ -n "$_src" ]]; then
    local _tmp
    _tmp="$(file__mktmpdir sf-create)/src"
    local -a _fh_args
    mapfile -t _fh_args < <(_sf_build_fetch_args "$_entry" "$_user")
    uri__fetch_asset "$_src" "${_fh_args[@]}" --file-dest "$_tmp"
    file__mkdir "$(dirname "$_dest")"
    file__cp "$_tmp" "$_dest"
    if [[ "$_preserve_perms" == "true" ]]; then
      local _src_mode _src_owner
      if [[ "$(os__kernel)" == "Darwin" ]]; then
        _src_mode="$(stat -f '%OLp' "$_src")"
        _src_owner="$(stat -f '%Su:%Sg' "$_src")"
      else
        _src_mode="$(stat -c '%a' "$_src")"
        _src_owner="$(stat -c '%U:%G' "$_src")"
      fi
      file__chmod "$_src_mode" "$_dest"
      file__chown "$_src_owner" "$_dest"
    fi
  else
    file__mkdir "$(dirname "$_dest")"
    printf '%s' "$_content" | file__tee "$_dest"
  fi

  _sf_apply_attrs "$_dest" "$_entry"
  _sf_record_state "$_user" create "$_dest" "$_created" "$_orig_hash" "" "$(_sf_hash "$_dest")" "$_bp"
}

_op_create_tree() {
  local _dest="$1" _src="$2" _entry="$3" _user="$4"
  # if_exists is NOT read here — it's inherited per-file by the nested
  # _op_create calls below (the merged entry object retains it).
  local _follow_symlinks
  _follow_symlinks="$(json__query -r 'if .follow_symlinks == null then "false" else (.follow_symlinks|tostring) end' <<< "$_entry")"
  local -a _include_patterns _exclude_patterns
  mapfile -t _include_patterns < <(json__string_or_array_lines "$_entry" include)
  mapfile -t _exclude_patterns < <(json__string_or_array_lines "$_entry" exclude)

  # Track the top-level dest directory itself for uninstall — this IS the
  # explicit target of the create op, unlike an implicit parent dir. Only
  # tracked if we created it; on uninstall rmdir succeeds only if the
  # directory is empty by then (i.e. all per-file entries were also removed).
  local _dir_existed=false
  [[ -d "$_dest" ]] && _dir_existed=true

  file__mkdir "$_dest"

  if ! $_dir_existed; then
    # shellcheck disable=SC2016
    _sf_state_upsert "$(_sf_state_file "$_user")" "$(json__query -n \
      --arg dest "$_dest" --arg ts "$(date -u +%FT%TZ)" \
      '{op:"mkdir",dest:$dest,created:true,original_hash:null,original_perms:null,
        current_hash:null,backup_path:null,timestamp_first:$ts,timestamp_last:$ts}')"
  fi

  local -a _find_args=("$_src" -type f)
  [[ "$_follow_symlinks" == "true" ]] && _find_args=(-L "${_find_args[@]}")

  # Build -name predicates from include/exclude glob patterns (relative to
  # src). A leading **/ is stripped since find already recurses. Patterns
  # containing a path separator are not supported via -name (documented
  # limitation). Default include (empty, or literal "**/*") means "all files".
  local -a _inc_args=() _exc_args=()
  if [[ ${#_include_patterns[@]} -gt 0 && "${_include_patterns[*]}" != "**/*" ]]; then
    local _first_inc=true _pat
    for _pat in "${_include_patterns[@]}"; do
      [[ -z "$_pat" ]] && continue
      _pat="${_pat#\*\*/}"
      if $_first_inc; then
        _inc_args+=(\( -name "$_pat")
        _first_inc=false
      else
        _inc_args+=(-o -name "$_pat")
      fi
    done
    [[ ${#_inc_args[@]} -gt 0 ]] && _inc_args+=(\))
  fi
  local _pat
  for _pat in "${_exclude_patterns[@]}"; do
    [[ -z "$_pat" ]] && continue
    _pat="${_pat#\*\*/}"
    _exc_args+=(-not -name "$_pat")
  done

  local _src_file
  while IFS= read -r _src_file; do
    [[ -z "$_src_file" ]] && continue
    local _rel="${_src_file#"$_src"/}"
    local _dest_file="${_dest}/${_rel}"
    local _file_entry
    # shellcheck disable=SC2016
    _file_entry="$(json__query --arg d "$_dest_file" --arg s "$_src_file" \
      '. + {dest: $d, src: $s}' <<< "$_entry")"
    _op_create "$_dest_file" "$_file_entry" "$_user"
  done < <(find "${_find_args[@]}" "${_inc_args[@]}" "${_exc_args[@]}")
}

_op_inject() {
  local _dest="$1" _entry="$2" _user="$3"

  # Batch every scalar/type field into one jq call. Marker/anchor extraction
  # is TYPE-GUARDED (not `.field.match // .field`) because jq errors when
  # indexing a plain-string value with `.match`/`.position` — a marker/anchor
  # is very commonly a plain string, so the naive `//`-fallback form would
  # crash on the common case rather than falling through.
  local -a _f
  mapfile -d '' -t _f < <(json__query_multi "$_entry" \
    '.begin_marker | type' \
    'if (.begin_marker|type)=="object" then .begin_marker.match else .begin_marker end' \
    'if (.begin_marker|type)=="object" then .begin_marker.text else .begin_marker end' \
    '.end_marker | type' \
    'if (.end_marker|type)=="object" then .end_marker.match else .end_marker end' \
    'if (.end_marker|type)=="object" then .end_marker.text else .end_marker end' \
    '.content // ""' '.src // ""' \
    '.if_not_found // "end_of_file"' \
    'if (.anchor|type)=="object" then .anchor.match else (.anchor // "") end' \
    'if (.anchor|type)=="object" then (.anchor.position // "after") else "after" end' \
    '.anchor_not_found // "fail"' \
    'if .leading_newline == null then "true" else (.leading_newline|tostring) end' \
    'if .trailing_newline == null then "true" else (.trailing_newline|tostring) end' \
    'if .rewrite_markers == null then "false" else (.rewrite_markers|tostring) end')
  local _bm_type="${_f[0]}" _bm_match="${_f[1]}" _bm_write="${_f[2]}"
  local _em_type="${_f[3]}" _em_match="${_f[4]}" _em_write="${_f[5]}"
  local _content="${_f[6]}" _src="${_f[7]}"
  local _if_not_found="${_f[8]}" _anchor="${_f[9]}" _anchor_pos="${_f[10]}" _anchor_not_found="${_f[11]}"
  local _leading_nl="${_f[12]}" _trailing_nl="${_f[13]}" _rewrite_markers="${_f[14]}"
  local _bm_is_regex=0 _em_is_regex=0
  [[ "$_bm_type" == "object" ]] && _bm_is_regex=1
  [[ "$_em_type" == "object" ]] && _em_is_regex=1

  # One login-shell call for all 7 content-type fields. Marker match patterns
  # are ERE (may contain characters the strict path-expander rejects) —
  # everything here uses the relaxed batch expander, never the strict one.
  local -a _exp
  mapfile -d '' -t _exp < <(users__expand_multi "${_SF_VAR_ENV_ARGS[@]}" ${_user:+--user "$_user"} -- \
    "$_bm_match" "$_bm_write" "$_em_match" "$_em_write" "$_anchor" "$_src" "$_content")
  local _raw_bm_match="$_bm_match" _raw_bm_write="$_bm_write" _raw_em_match="$_em_match" \
    _raw_em_write="$_em_write" _raw_anchor="$_anchor" _raw_src="$_src" _raw_content="$_content"
  _bm_match="$(_sf_strict_check "${_exp[0]}" "$_entry" "$_raw_bm_match")" || return 1
  _bm_write="$(_sf_strict_check "${_exp[1]}" "$_entry" "$_raw_bm_write")" || return 1
  _em_match="$(_sf_strict_check "${_exp[2]}" "$_entry" "$_raw_em_match")" || return 1
  _em_write="$(_sf_strict_check "${_exp[3]}" "$_entry" "$_raw_em_write")" || return 1
  _anchor="$(_sf_strict_check "${_exp[4]}" "$_entry" "$_raw_anchor")" || return 1
  _src="$(_sf_strict_check "${_exp[5]}" "$_entry" "$_raw_src")" || return 1
  _content="$(_sf_strict_check "${_exp[6]}" "$_entry" "$_raw_content")" || return 1

  # If src is set, content comes from the fetch, not the manifest — expand it
  # separately (unavoidable extra call: unknown until after the fetch).
  if [[ -n "$_src" ]]; then
    local _tmp
    _tmp="$(file__mktmpdir sf-inject)/content"
    local -a _fh_args
    mapfile -t _fh_args < <(_sf_build_fetch_args "$_entry" "$_user")
    uri__fetch_asset "$_src" "${_fh_args[@]}" --file-dest "$_tmp"
    _content="$(_sf_expand_content "$(cat "$_tmp")" "$_entry" "$_user")" || return 1
  fi

  [[ ! -f "$_dest" ]] && {
    file__mkdir "$(dirname "$_dest")"
    printf '' | file__tee "$_dest"
  }

  local _orig_hash
  _orig_hash="$(_sf_hash "$_dest")"

  local _result _rc=0
  _result="$(
    _SF_AWK_CONTENT="$_content" _SF_AWK_BW="$_bm_write" _SF_AWK_EW="$_em_write" \
      _SF_AWK_BM="$_bm_match" _SF_AWK_EM="$_em_match" _SF_AWK_ANCHOR="$_anchor" \
      awk \
      -v bm_re="$_bm_is_regex" -v em_re="$_em_is_regex" \
      -v inf="$_if_not_found" -v anc_pos="$_anchor_pos" -v anf="$_anchor_not_found" \
      -v lead_nl="$_leading_nl" -v trail_nl="$_trailing_nl" -v rew="$_rewrite_markers" \
      -f "${_FEAT_FILES_DIR}/inject.awk" \
      "$_dest"
  )" || _rc=$?
  case $_rc in
    0) : ;;
    2)
      logging__error "inject: begin_marker found but no end_marker in ${_dest}."
      return 1
      ;;
    3)
      logging__error "inject: multiple begin/end marker pairs found in ${_dest}."
      return 1
      ;;
    4)
      logging__error "inject: anchor not found in ${_dest} (anchor_not_found=fail)."
      return 1
      ;;
    5)
      logging__error "inject: block not found in ${_dest} (if_not_found=fail)."
      return 1
      ;;
    *)
      logging__error "inject: awk failed with exit code ${_rc} on ${_dest}."
      return 1
      ;;
  esac

  printf '%s' "$_result" | file__tee "$_dest"

  _sf_apply_attrs "$_dest" "$_entry"

  local _inj_created=false
  [[ "$_orig_hash" == "null" ]] && _inj_created=true
  local _extra
  # shellcheck disable=SC2016
  _extra="$(json__query -n --arg bm "$_bm_write" --arg em "$_em_write" '{begin_marker:$bm, end_marker:$em}')"
  _sf_record_state "$_user" inject "$_dest" "$_inj_created" "$_orig_hash" "" "$(_sf_hash "$_dest")" "" "$_extra"
}

_op_delete() {
  local _dest="$1" _entry="$2" _user="$3"
  local -a _f
  mapfile -d '' -t _f < <(json__query_multi "$_entry" \
    'if .recursive == null then "false" else (.recursive|tostring) end' \
    '.if_not_exists // "skip"' '.backup // ""')
  local _recursive="${_f[0]}" _if_not_exists="${_f[1]}" _backup_val="${_f[2]}"

  if [[ ! -e "$_dest" ]]; then
    [[ "$_if_not_exists" == "fail" ]] && {
      logging__error "delete: ${_dest} not found."
      return 1
    }
    return 0
  fi

  if [[ -d "$_dest" && ! -L "$_dest" && "$_recursive" != "true" ]]; then
    if [[ -n "$(ls -A "$_dest" 2> /dev/null)" ]]; then
      logging__error "delete: ${_dest} is a non-empty directory; set recursive:true to force."
      return 1
    fi
  fi

  local _bp
  _bp="$(_sf_maybe_backup "$_dest" "$_backup_val")"
  file__rm -rf "$_dest"

  _sf_record_state "$_user" delete "$_dest" false "" "" "" "$_bp"
}

_op_symlink() {
  local _dest="$1" _entry="$2" _user="$3"
  local -a _f
  mapfile -d '' -t _f < <(json__query_multi "$_entry" \
    '.src' '.if_exists // "skip"' '.chmod // ""' '.owner // ""' '.group // ""')
  local _src="${_f[0]}" _if_exists="${_f[1]}" _chmod_val="${_f[2]}" _owner="${_f[3]}" _group="${_f[4]}"
  _src="$(_sf_expand_content "$_src" "$_entry" "$_user")" || return 1

  if [[ -L "$_dest" || -e "$_dest" ]]; then
    case "$_if_exists" in
      skip)
        logging__skip "${_dest} already exists; skipping."
        return 0
        ;;
      fail)
        logging__error "${_dest} already exists (if_exists:fail)."
        return 1
        ;;
      overwrite) file__rm -f "$_dest" ;;
    esac
  fi
  file__mkdir "$(dirname "$_dest")"
  file__ln -s "$_src" "$_dest"

  # chmod on a symlink typically follows the link and modifies the TARGET on
  # POSIX systems, not the link itself — silently "applying" it would be a
  # dangerous surprise, so warn instead of running it. owner/group ARE
  # meaningful on the link itself via chown -h, so those are applied.
  [[ -n "$_chmod_val" ]] && logging__warn "symlink: chmod is not applied to symlinks (it would follow the link and affect its target); ignoring chmod:${_chmod_val} on ${_dest}."
  [[ -n "$_owner" || -n "$_group" ]] && file__chown -h "${_owner}:${_group}" "$_dest"

  _sf_record_state "$_user" symlink "$_dest" true
}

_op_mkdir() {
  local _dest="$1" _entry="$2" _user="$3"
  local -a _f
  mapfile -d '' -t _f < <(json__query_multi "$_entry" \
    '.if_exists // "skip"' '.chmod // ""' '.owner // ""' '.group // ""' \
    'if .recursive_attrs == null then "false" else (.recursive_attrs|tostring) end')
  local _if_exists="${_f[0]}" _chmod_val="${_f[1]}" _owner="${_f[2]}" _group="${_f[3]}" _recursive_attrs="${_f[4]}"

  local _existing=false
  [[ -d "$_dest" ]] && _existing=true

  if $_existing; then
    case "$_if_exists" in
      skip)
        logging__skip "${_dest} already exists; skipping."
        return 0
        ;;
      fail)
        logging__error "${_dest} already exists (if_exists:fail)."
        return 1
        ;;
      overwrite) : ;; # fall through — apply chmod/chown to the existing dir below
    esac
  fi

  # Track newly-created intermediate directories, for recursive_attrs.
  local -a _new_dirs=()
  if [[ "$_recursive_attrs" == "true" ]] && ! $_existing; then
    local _p="$_dest"
    while [[ ! -d "$_p" && "$_p" != "/" ]]; do
      _new_dirs=("$_p" "${_new_dirs[@]}")
      _p="$(dirname "$_p")"
    done
  fi

  file__mkdir "$_dest"

  if [[ "$_recursive_attrs" == "true" ]] && ! $_existing; then
    local _d
    for _d in "${_new_dirs[@]}"; do
      [[ -n "$_chmod_val" ]] && file__chmod "$_chmod_val" "$_d"
      [[ -n "$_owner" || -n "$_group" ]] && file__chown "${_owner}:${_group}" "$_d"
    done
  else
    [[ -n "$_chmod_val" ]] && file__chmod "$_chmod_val" "$_dest"
    [[ -n "$_owner" || -n "$_group" ]] && file__chown "${_owner}:${_group}" "$_dest"
  fi

  # Only track state (for uninstall removal) when we actually created the
  # dir. Applying attrs to a pre-existing dir (if_exists:overwrite) is a
  # one-way modification.
  $_existing && return 0
  _sf_record_state "$_user" mkdir "$_dest" true
}

_op_chmod() {
  local _dest="$1" _entry="$2" _user="$3"
  local -a _f
  mapfile -d '' -t _f < <(json__query_multi "$_entry" \
    '.chmod // ""' '.owner // ""' '.group // ""' \
    'if .recursive == null then "false" else (.recursive|tostring) end' '.if_not_exists // "fail"')
  local _chmod_val="${_f[0]}" _owner="${_f[1]}" _group="${_f[2]}" _recursive="${_f[3]}" _if_not_exists="${_f[4]}"

  if [[ ! -e "$_dest" ]]; then
    [[ "$_if_not_exists" == "fail" ]] && {
      logging__error "chmod: ${_dest} not found."
      return 1
    }
    return 0
  fi

  local _orig_perms
  if [[ "$(os__kernel)" == "Darwin" ]]; then
    _orig_perms="$(stat -f '%OLp %Su %Sg' "$_dest")"
  else
    _orig_perms="$(stat -c '%a %U %G' "$_dest")"
  fi

  local -a _rflag=()
  [[ "$_recursive" == "true" ]] && _rflag=(-R)
  [[ -n "$_chmod_val" ]] && file__chmod "${_rflag[@]}" "$_chmod_val" "$_dest"
  [[ -n "$_owner" || -n "$_group" ]] && file__chown "${_rflag[@]}" "${_owner}:${_group}" "$_dest"

  _sf_record_state "$_user" chmod "$_dest" false "" "$_orig_perms"
}

_op_move() {
  local _dest="$1" _entry="$2" _user="$3"
  local -a _f
  mapfile -d '' -t _f < <(json__query_multi "$_entry" \
    '.src' '.if_exists // "fail"' '.if_not_exists // "fail"')
  local _src="${_f[0]}" _if_exists="${_f[1]}" _if_not_exists="${_f[2]}"
  _src="$(_sf_expand_content "$_src" "$_entry" "$_user")" || return 1

  if [[ ! -e "$_src" ]]; then
    [[ "$_if_not_exists" == "fail" ]] && {
      logging__error "move: src '${_src}' not found."
      return 1
    }
    return 0
  fi

  if [[ -e "$_dest" ]]; then
    case "$_if_exists" in
      skip)
        logging__skip "move: ${_dest} already exists; skipping."
        return 0
        ;;
      fail)
        logging__error "move: ${_dest} already exists (if_exists:fail)."
        return 1
        ;;
      overwrite) file__rm -rf "$_dest" ;;
    esac
  fi

  local _orig_hash
  _orig_hash="$(_sf_hash "$_src")"
  file__mkdir "$(dirname "$_dest")"
  file__mv "$_src" "$_dest"

  local _extra
  # shellcheck disable=SC2016
  _extra="$(json__query -n --arg s "$_src" '{src:$s}')"
  _sf_record_state "$_user" move "$_dest" false "$_orig_hash" "" "$_orig_hash" "" "$_extra"
}

_op_touch() {
  local _dest="$1" _entry="$2" _user="$3"
  # touch is the one op that defaults to "overwrite" (bump mtime every run) —
  # its primary use case is a last-ran marker; skip-by-default would defeat that.
  local -a _f
  mapfile -d '' -t _f < <(json__query_multi "$_entry" \
    '.if_exists // "overwrite"' '.chmod // ""' '.owner // ""' '.group // ""')
  local _if_exists="${_f[0]}"

  local _created=false
  if [[ ! -e "$_dest" ]]; then
    file__mkdir "$(dirname "$_dest")"
    printf '' | file__tee "$_dest"
    _created=true
  else
    case "$_if_exists" in
      skip) logging__skip "${_dest} already exists; skipping mtime update." ;;
      fail)
        logging__error "${_dest} already exists (if_exists:fail)."
        return 1
        ;;
      overwrite) touch "$_dest" 2> /dev/null || users__run_privileged touch "$_dest" ;;
    esac
  fi

  _sf_apply_attrs "$_dest" "$_entry"

  $_created || return 0
  _sf_record_state "$_user" touch "$_dest" true
}

# ============================================================================
# Uninstall
# ============================================================================

_do_uninstall() {
  local _sys_state="${_FEAT_SHARE_DIR_ROOT}/state.json"
  if [[ -f "$_sys_state" ]]; then
    _uninstall_state_file "$_sys_state" ""
    file__rm -f "$_sys_state"
  fi

  local _user
  for _user in "${_SF_USERS[@]}"; do
    [[ -z "$_user" ]] && continue
    local _state
    _state="$(_sf_state_file "$_user")"
    if [[ -f "$_state" ]]; then
      _uninstall_state_file "$_state" "$_user"
      file__rm -f "$_state"
    fi
  done
}

_uninstall_state_file() {
  local _state_file="$1" _user="$2"
  local _state
  _state="$(_sf_state_read "$_state_file")"

  # Reverse order, streamed as NDJSON (same O(n^2)-avoidance as _apply_config).
  local _ndjson
  _ndjson="$(json__query -c '.entries | reverse | .[]' <<< "$_state")"

  local _entry
  while IFS= read -r _entry; do
    [[ -z "$_entry" ]] && continue
    local -a _f
    mapfile -d '' -t _f < <(json__query_multi "$_entry" \
      '.op' '.dest' 'if .created == null then "false" else (.created|tostring) end' '.current_hash // ""' \
      '.backup_path // ""' '.begin_marker // ""' '.end_marker // ""' \
      '.original_perms // ""' '.src // ""')
    local _op="${_f[0]}" _dest="${_f[1]}" _created="${_f[2]}" _cur_hash="${_f[3]}" \
      _bp="${_f[4]}" _bm="${_f[5]}" _em="${_f[6]}" _orig_perms="${_f[7]}" _orig_src="${_f[8]}"

    case "$_op" in
      create)
        local _actual_hash
        _actual_hash="$(_sf_hash "$_dest")"
        if [[ "$_actual_hash" != "$_cur_hash" ]]; then
          logging__warn "Uninstall: ${_dest} was externally modified; leaving in place."
        else
          file__rm -f "$_dest"
          if [[ -n "$_bp" && -f "$_bp" ]]; then
            file__mv "$_bp" "$_dest"
          elif [[ "$_created" != "true" ]]; then
            logging__warn "Uninstall: original of ${_dest} cannot be restored (no backup taken)."
          fi
        fi
        ;;
      inject)
        if [[ -f "$_dest" ]] && grep -qF "$_bm" "$_dest" 2> /dev/null; then
          local _result
          _result="$(
            _SF_RM_BM="$_bm" _SF_RM_EM="$_em" awk '
              BEGIN { bm=ENVIRON["_SF_RM_BM"]; em=ENVIRON["_SF_RM_EM"]; skip=0 }
              $0==bm         { skip=1; next }
              skip && $0==em { skip=0; next }
              !skip          { print }
            ' "$_dest"
          )"
          printf '%s' "$_result" | file__tee "$_dest"
          [[ "$_created" == "true" && ! -s "$_dest" ]] && file__rm -f "$_dest"
        else
          logging__warn "Uninstall: inject markers not found in ${_dest}; may already be removed."
        fi
        ;;
      delete)
        if [[ -n "$_bp" && -f "$_bp" ]]; then
          file__mv "$_bp" "$_dest"
        else
          logging__warn "Uninstall: ${_dest} was deleted; no backup to restore."
        fi
        ;;
      symlink | touch)
        [[ "$_created" == "true" ]] && file__rm -f "$_dest"
        ;;
      mkdir)
        if [[ "$_created" == "true" ]]; then
          file__rm -d "$_dest" 2> /dev/null || logging__warn "Uninstall: ${_dest} is not empty; skipping rmdir."
        fi
        ;;
      move)
        if [[ -e "$_orig_src" ]]; then
          logging__warn "Uninstall: ${_orig_src} now exists; cannot move ${_dest} back."
        else
          file__mv "$_dest" "$_orig_src"
        fi
        ;;
      chmod)
        if [[ -n "$_orig_perms" && -e "$_dest" ]]; then
          local _mode _owner _group
          read -r _mode _owner _group <<< "$_orig_perms"
          file__chmod "$_mode" "$_dest"
          file__chown "${_owner}:${_group}" "$_dest"
        fi
        ;;
    esac
  done <<< "$_ndjson"
}
