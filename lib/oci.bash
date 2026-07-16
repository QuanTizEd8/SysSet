# shellcheck shell=bash
# OCI and GHCR container registry helpers: resolve tags, pull feature artifacts.
#
# Provides helpers for constructing `ghcr.io` image references, listing tags,
# pulling feature artifacts, and resolving version specs from OCI tag lists.
# Requires `oras` to be available; `oci__ensure_oras` installs it if absent.

_OCI__ORAS_MIN_VERSION="${_OCI__ORAS_MIN_VERSION:-1.2.0}"
_OCI__AUTH_LOADED=0
declare -gA _OCI__AUTH_USER=()
declare -gA _OCI__AUTH_TOKEN=()
declare -gA _OCI__AUTH_DONE=()

_oci__is_registry_host_like() {
  # @brief _oci__is_registry_host_like <host> — Return 0 when `<host>` looks like an OCI registry hostname.
  #
  # Accepts `localhost`, `localhost:<port>`, dotted hostnames (e.g. `ghcr.io`),
  # and IPv6 bracket addresses. Single-label names without dots (e.g. bare `myrepo`)
  # are rejected because they cannot be distinguished from a repository path component.
  #
  # Args:
  #   <host>  Hostname string to test (no scheme, no path).
  #
  # Returns: 0 if host-like, 1 otherwise.
  local _host="${1-}"
  [[ -n "$_host" ]] || return 1
  [[ "$_host" == "localhost" || "$_host" =~ ^localhost:[0-9]+$ ]] && return 0
  [[ "$_host" == *.* ]] && return 0
  [[ "$_host" =~ ^\[[0-9A-Fa-f:.]+\](:[0-9]+)?$ ]] && return 0
  return 1
}

_oci__registry_from_ref_or_repo() {
  # @brief _oci__registry_from_ref_or_repo <ref> — Extract the registry hostname from a full OCI reference or repository string.
  #
  # Strips `http://` and `https://` scheme prefixes before extraction. Returns
  # the first path component (everything before the first `/`). Returns 1 when
  # the input has no `/` and therefore cannot contain a registry component.
  #
  # Args:
  #   <ref>  Full OCI reference or repository string (e.g. `ghcr.io/owner/image:tag`).
  #
  # Stdout: registry hostname (e.g. `ghcr.io`).
  # Returns: 0 on success, 1 if no registry component is present.
  local _v="${1-}"
  case "$_v" in
    http://*) _v="${_v#http://}" ;;
    https://*) _v="${_v#https://}" ;;
  esac
  [[ "$_v" == */* ]] || return 1
  printf '%s\n' "${_v%%/*}"
}

_oci__normalize_target() {
  # @brief _oci__normalize_target <ref> — Strip scheme prefix, detect plain-HTTP flag, and print `<target>\t<plain>`.
  #
  # Converts an OCI reference that may carry an `http://` or `https://` scheme
  # into the scheme-free form expected by `oras`. Sets the plain-HTTP flag to 1
  # for `http://` URIs and for `localhost`/`127.0.0.1` targets (which oras
  # requires plain-HTTP mode for). The two-field output is designed for
  # `IFS=$'\t' read -r _target _plain <<< "$(…)"`.
  #
  # Args:
  #   <ref>  OCI reference possibly prefixed with `http://` or `https://`.
  #
  # Stdout: `<scheme-free-ref>\t<plain>` where `<plain>` is `0` or `1`.
  local _in="${1-}" _plain=0 _host
  case "$_in" in
    http://*)
      _in="${_in#http://}"
      _plain=1
      ;;
    https://*) _in="${_in#https://}" ;;
  esac
  _host="${_in%%/*}"
  _host="${_host%%:*}"
  if [[ "$_host" == "localhost" || "$_host" == "127.0.0.1" ]]; then
    _plain=1
  fi
  printf '%s\t%s\n' "$_in" "$_plain"
}

_oci__retryable_error() {
  # @brief _oci__retryable_error <exit-code> <stderr-file> — Return success unless an ORAS failure is certainly persistent for an unchanged read operation.
  #
  # Registry response wording is client- and version-specific. OCI reads are
  # idempotent, so retry unknown failures (including unknown manifest/tag
  # responses that may be caused by publication or replication lag) and reject
  # only clear reference, credential, authorisation, or local TLS errors.
  local _rc="$1" _stderr_file="$2"
  [ "$_rc" -ne 0 ] || return 1
  if grep -Eiq \
    'denied: requested access|requested access to the resource is denied|unauthorized|authentication required|authentication failed|invalid (reference|repository|image name)|invalid reference format|unsupported protocol|x509: certificate signed by unknown authority|certificate verify failed' \
    "$_stderr_file"; then
    return 1
  fi
  return 0
}

_oci__oras_retry() {
  # @brief _oci__oras_retry <oras-args>... — Run one read-only ORAS operation with retry-by-default classification.
  net__fetch_with_retry --retry-if _oci__retryable_error "$@"
}

_oci__oras_capture() {
  # @brief _oci__oras_capture <target> <plain> [<prefix-args> -- <suffix-args>] — Run an oras command against `<target>`, retrying with plain-HTTP variants if `<plain>` is 1.
  #
  # Arguments before `--` are the command prefix (e.g. `oras repo tags`); arguments
  # after `--` are appended after `<target>`. When `<plain>` is `1`, tries three
  # strategies in order: `ORAS_PLAIN_HTTP=1`, `oras --plain-http <sub> <target>`,
  # then `<prefix> --plain-http <target>`. Each strategy uses retry-by-default
  # retries; stderr is suppressed in all cases.
  #
  # Args:
  #   <target>      Scheme-free OCI reference or repository (from _oci__normalize_target).
  #   <plain>       `0` for normal TLS; `1` to enable plain-HTTP fallbacks.
  #   <prefix-args> Command and sub-command components (e.g. `oras` `repo` `tags`).
  #   --            Separator between prefix and suffix args (optional).
  #   <suffix-args> Additional arguments appended after <target>.
  #
  # Returns: 0 on success, 1 if all variants fail.
  local _target="${1-}" _plain="${2-}"
  shift 2
  local -a _prefix=() _suffix=() _global_plain=()
  local _split=0 _arg
  for _arg in "$@"; do
    if [[ "$_arg" == "--" && "$_split" -eq 0 ]]; then
      _split=1
      continue
    fi
    if [[ "$_split" -eq 0 ]]; then
      _prefix+=("$_arg")
    else
      _suffix+=("$_arg")
    fi
  done
  [[ -n "$_target" ]] || {
    logging__error "oras target reference is empty."
    return 1
  }
  [[ "${#_prefix[@]}" -gt 0 ]] || {
    logging__error "oras command prefix is empty."
    return 1
  }
  if [[ "$_plain" == "1" ]]; then
    # Some oras subcommands honor plain-http only via env or global flag.
    ORAS_PLAIN_HTTP=1 _oci__oras_retry "${_prefix[@]}" "$_target" "${_suffix[@]}" 2> /dev/null && return 0
    if [[ "${_prefix[0]}" == "oras" ]]; then
      _global_plain=("oras" --plain-http)
      if [[ "${#_prefix[@]}" -gt 1 ]]; then
        _global_plain+=("${_prefix[@]:1}")
      fi
      _oci__oras_retry "${_global_plain[@]}" "$_target" "${_suffix[@]}" 2> /dev/null && return 0
    fi
    _oci__oras_retry "${_prefix[@]}" --plain-http "$_target" "${_suffix[@]}" 2> /dev/null && return 0
    return 1
  fi
  _oci__oras_retry "${_prefix[@]}" "$_target" "${_suffix[@]}" 2> /dev/null
}

_oci__load_auth_map() {
  # @brief _oci__load_auth_map — Parse `SYSSET_OCI_AUTH` (or `SYSSET_OCI_AUTH_FILE`) into `_OCI__AUTH_USER` and `_OCI__AUTH_TOKEN` maps. Idempotent.
  #
  # Expected format: comma-separated `registry|username|token` triples, e.g.:
  #   `ghcr.io|myuser|ghp_token,registry.example.com|robot|s3cr3t`
  # Fields with missing delimiters or empty components are silently skipped.
  # Called lazily by `_oci__ensure_auth_for`; subsequent calls are no-ops.
  #
  # Side effects: populates `_OCI__AUTH_USER[registry]` and `_OCI__AUTH_TOKEN[registry]`.
  [[ "$_OCI__AUTH_LOADED" -eq 1 ]] && return 0
  _OCI__AUTH_LOADED=1
  local _src="${SYSSET_OCI_AUTH-}" _entry _reg _usr _tok
  if [[ -z "$_src" && -n "${SYSSET_OCI_AUTH_FILE-}" && -f "${SYSSET_OCI_AUTH_FILE}" ]]; then
    _src="$(tr -d '\n' < "${SYSSET_OCI_AUTH_FILE}" 2> /dev/null || true)"
  fi
  [[ -n "$_src" ]] || return 0
  for _entry in ${_src//,/ }; do
    _reg="${_entry%%|*}"
    [[ "$_entry" == *"|"* ]] || continue
    _usr="${_entry#*|}"
    [[ "$_usr" == *"|"* ]] || continue
    _tok="${_usr#*|}"
    _usr="${_usr%%|*}"
    [[ -n "$_reg" && -n "$_usr" && -n "$_tok" ]] || continue
    _OCI__AUTH_USER["$_reg"]="$_usr"
    _OCI__AUTH_TOKEN["$_reg"]="$_tok"
  done
  return 0
}

_oci__ensure_auth_for() {
  # @brief _oci__ensure_auth_for <target> — Log in to the registry for `<target>` if credentials are available. Idempotent per registry.
  #
  # Credential resolution order:
  #   1. SYSSET_OCI_AUTH / SYSSET_OCI_AUTH_FILE (explicit multi-registry map).
  #   2. GITHUB_TOKEN — used automatically for ghcr.io with username
  #      `x-access-token` (standard GitHub Container Registry token auth).
  # Registries with no credentials configured are silently skipped (returns 0).
  # Once a registry has been attempted, it is marked done so subsequent calls
  # for the same registry are no-ops.
  # Xtrace is suppressed around the login call to prevent token leaking in CI logs.
  #
  # Args:
  #   <target>  Scheme-free OCI reference (e.g. `ghcr.io/owner/repo:tag`).
  #
  # Returns: 0 on success or when no credentials are configured, 1 on login failure.
  local _target="${1-}" _reg _usr _tok _tmp
  oci__ensure_oras
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "'oras' is required but could not be set up."
    return "$_rc"
  }
  _reg="$(_oci__registry_from_ref_or_repo "$_target" 2> /dev/null || true)"
  [[ -n "$_reg" ]] || return 0
  [[ -n "${_OCI__AUTH_DONE[$_reg]+x}" ]] && return 0
  _oci__load_auth_map
  _usr="${_OCI__AUTH_USER[$_reg]-}"
  _tok="${_OCI__AUTH_TOKEN[$_reg]-}"
  # Fall back to GITHUB_TOKEN for ghcr.io when no explicit credentials are set.
  if [[ -z "$_usr" || -z "$_tok" ]] && [[ "$_reg" == "ghcr.io" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
    _usr="x-access-token"
    _tok="${GITHUB_TOKEN}"
  fi
  if [[ -z "$_usr" || -z "$_tok" ]]; then
    _OCI__AUTH_DONE["$_reg"]=1
    return 0
  fi
  _tmp="$(mktemp)"
  local _xt=false
  case "$-" in *x*) _xt=true ;; esac
  { set +x; } 2> /dev/null
  printf '%s' "$_tok" > "$_tmp"
  if oras login "$_reg" -u "$_usr" --password-stdin < "$_tmp" > /dev/null 2>&1; then
    _OCI__AUTH_DONE["$_reg"]=1
  else
    rm -f "$_tmp"
    [[ "$_xt" == true ]] && { set -x; } 2> /dev/null
    logging__error "failed to authenticate to '${_reg}'."
    return 1
  fi
  rm -f "$_tmp"
  [[ "$_xt" == true ]] && { set -x; } 2> /dev/null
  return 0
}

oci__ghcr_image_ref() {
  # @brief oci__ghcr_image_ref <namespace/path> <image-name> <tag> — Print a fully-qualified `ghcr.io` image reference.
  #
  # Args:
  #   <namespace/path>  GitHub namespace and optional path prefix (e.g. `owner/repo`).
  #   <image-name>      Image name (e.g. `install-pixi`).
  #   <tag>             Image tag (e.g. `1.0.0`).
  #
  # Stdout: `ghcr.io/<namespace>/<image-name>:<tag>`.
  local _ns="${1-}" _name="${2-}" _tag="${3-}"
  printf 'ghcr.io/%s/%s:%s\n' "$_ns" "$_name" "$_tag"
}

oci__ensure_oras() {
  # @brief oci__ensure_oras — Ensure `oras` is available and meets the minimum required version, auto-installing it if needed.
  #
  # Returns: 0 on success, 1 if oras cannot be installed or is below the minimum version.
  local _bin=""
  _bin="$(command -v oras 2> /dev/null || true)"
  if [[ -z "$_bin" ]]; then
    logging__info "oras not found — installing."
    _bin="$(bootstrap__oras "${SYSSET_ORAS_VERSION:-latest}" 2> /dev/null || true)"
    [[ -n "$_bin" ]] || _bin="$(command -v oras 2> /dev/null || true)"
  fi
  if [[ -z "$_bin" ]]; then
    ospkg__install_tracked "lib-oci" oras >&2
    _bin="$(command -v oras 2> /dev/null || true)"
  fi
  [[ -n "$_bin" ]] || {
    logging__error "oras could not be installed."
    return 1
  }

  local _ver
  _ver="$(ver__extract_version "$("$_bin" version 2> /dev/null | head -n1)")"
  [[ -n "$_ver" ]] || {
    logging__warn "could not determine oras version; continuing."
    return 0
  }
  ver__semver_ge "$_ver" "$_OCI__ORAS_MIN_VERSION"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "oras version ${_ver} is below required ${_OCI__ORAS_MIN_VERSION}."
    return "$_rc"
  }
  return 0
}

oci__is_feature_ref_key() {
  # @brief oci__is_feature_ref_key <key> — Return 0 when `<key>` looks like an OCI image reference (registry-host/path[:tag]).
  #
  # Args:
  #   <key>  Key string to test.
  local _k="${1-}" _host _rest
  [[ "$_k" == *"/"* ]] || return 1
  _host="${_k%%/*}"
  _rest="${_k#*/}"
  [[ -n "$_host" && -n "$_rest" ]] || return 1
  if ! _oci__is_registry_host_like "$_host"; then return 1; fi
  [[ "$_k" == *@sha256:* || "$_k" == *:* ]] || return 1
  return 0
}

_oci__repo_from_ref() {
  # @brief _oci__repo_from_ref <ref> — Extract the repository portion of an OCI reference (everything before the tag or digest).
  #
  # Handles digest references (`repo@sha256:…`), tagged references (`repo:tag`),
  # and bare repositories. Input is lowercased before processing.
  #
  # Args:
  #   <ref>  Full OCI reference string.
  #
  # Stdout: repository portion without tag or digest.
  local _ref="${1,,}"
  if [[ "$_ref" == *@sha256:* ]]; then
    printf '%s\n' "${_ref%@sha256:*}"
    return 0
  fi
  local _tail="${_ref##*/}"
  if [[ "$_tail" == *:* ]]; then
    printf '%s\n' "${_ref%:*}"
  else
    printf '%s\n' "$_ref"
  fi
}

_oci__tag_from_ref() {
  # @brief _oci__tag_from_ref <ref> — Extract the tag from an OCI reference. Returns 1 for digest references or untagged refs.
  #
  # Args:
  #   <ref>  Full OCI reference string (e.g. `ghcr.io/owner/repo:1.2.3`).
  #
  # Stdout: tag string (e.g. `1.2.3`).
  # Returns: 0 if a tag is present, 1 for digest refs (`@sha256:…`) or bare repos.
  local _ref="${1-}" _tail
  [[ "$_ref" == *@sha256:* ]] && return 1
  _tail="${_ref##*/}"
  [[ "$_tail" == *:* ]] || return 1
  printf '%s\n' "${_tail#*:}"
}

oci__list_tags() {
  # @brief oci__list_tags <repo> — Print one tag per line for an OCI repository using `oras repo tags`.
  #
  # Args:
  #   <repo>  OCI repository reference (e.g. `ghcr.io/owner/repo`).
  #
  # Stdout: one tag per line.
  #
  # Returns: 0 on success, 1 if tags cannot be listed.
  local _repo="${1-}"
  local _target _plain
  [[ -n "$_repo" ]] || {
    logging__error "OCI repository reference is empty."
    return 1
  }
  oci__ensure_oras
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "'oras' is required but could not be set up."
    return "$_rc"
  }
  _oci__ensure_auth_for "$_repo"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "OCI registry authentication failed for '${_repo}'."
    return "$_rc"
  }
  IFS=$'\t' read -r _target _plain <<< "$(_oci__normalize_target "$_repo")"
  local _raw
  _raw="$(_oci__oras_capture "$_target" "$_plain" oras repo tags || true)"
  if [[ -z "${_raw:-}" ]]; then
    logging__error "failed to list tags for ${_repo}."
    return 1
  fi
  printf '%s\n' "$_raw" | tr -d '\r' | sed '/^[[:space:]]*$/d'
}

_oci__highest_semver() {
  # @brief _oci__highest_semver <tags> [<allow_pre>] — From a newline-separated list of OCI tags, print the highest stable (or pre-release) semver.
  #
  # Filters the list to semver-shaped tags, optionally including pre-releases,
  # then picks the highest version via `sort -V`. Tags that are not valid semver
  # (e.g. `latest`, `edge`) are silently ignored.
  #
  # Args:
  #   <tags>       Newline-separated tag list.
  #   [allow_pre]  `true` to include pre-release versions; default `false`.
  #
  # Stdout: highest matching semver string (no leading `v`).
  # Returns: 0 if at least one semver tag is found, 1 if the filtered list is empty.
  local _tags="${1-}" _allow_pre="${2-false}" _t _sv _list=""
  while IFS= read -r _t; do
    [[ -z "$_t" ]] && continue
    _sv="$(ver__extract_version --full-match --keep-suffix "$_t")"
    [[ -n "$_sv" ]] || continue
    if [[ "$_allow_pre" != true ]] && ! ver__semver_is_final "$_sv"; then
      continue
    fi
    _list="${_list}${_sv}"$'\n'
  done <<< "$_tags"
  [[ -n "$_list" ]] || {
    logging__error "no semver tags found in tag list."
    return 1
  }
  printf '%s' "$_list" | sed '/^$/d' | sort -V | tail -n1
}

oci__resolve_version() {
  # @brief oci__resolve_version <repo> [<spec>] — Resolve a version spec to a concrete tag from an OCI repository's tag list.
  #
  # `<spec>` may be empty/`latest`, a full semver (`1.2.3`), a major (`1`),
  # a major.minor (`1.2`), or any literal tag name.
  #
  # Args:
  #   <repo>   OCI repository reference (e.g. `ghcr.io/owner/repo`).
  #   <spec>   Version specification (optional; defaults to `latest`).
  #
  # Stdout: the resolved tag string.
  #
  # Returns: 0 on success, 1 if no matching tag is found.
  local _repo="${1-}" _spec="${2-}"
  [[ -n "$_repo" ]] || {
    logging__error "OCI repository reference is empty."
    return 1
  }
  local _tags _hi
  _tags="$(oci__list_tags "$_repo")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to list tags for '${_repo}'."
    return "$_rc"
  }

  case "${_spec}" in
    "" | latest)
      if printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "latest"; then
        printf 'latest\n'
        return 0
      fi
      _hi="$(_oci__highest_semver "$_tags" false 2> /dev/null || true)"
      [[ -n "$_hi" ]] || {
        logging__error "no matching tags for '${_repo}'."
        return 1
      }
      printf '%s\n' "$_hi"
      return 0
      ;;
  esac

  local _norm="${_spec#v}" _allow_pre=false
  ! ver__semver_is_final "$_norm" && _allow_pre=true
  if [[ "$_norm" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    if printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "$_norm"; then
      printf '%s\n' "$_norm"
      return 0
    fi
    logging__error "no tag found for spec '${_spec}' in '${_repo}'."
    return 1
  fi

  if [[ ! "$_norm" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    if printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "$_spec"; then
      printf '%s\n' "$_spec"
      return 0
    fi
    if [[ "$_spec" == v* ]] && printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "${_spec#v}"; then
      printf '%s\n' "${_spec#v}"
      return 0
    fi
  fi

  local _cands="" _t _sv
  while IFS= read -r _t; do
    _sv="$(ver__extract_version --full-match --keep-suffix "$_t")"
    [[ -n "$_sv" ]] || continue
    if [[ "$_norm" =~ ^[0-9]+$ ]]; then
      [[ "$_sv" == "${_norm}."* ]] || continue
    elif [[ "$_norm" =~ ^[0-9]+\.[0-9]+$ ]]; then
      [[ "$_sv" == "${_norm}."* ]] || continue
    else
      continue
    fi
    if [[ "$_allow_pre" != true ]] && ! ver__semver_is_final "$_sv"; then
      continue
    fi
    _cands="${_cands}${_sv}"$'\n'
  done <<< "$_tags"
  [[ -n "$_cands" ]] || {
    logging__error "no tag found for spec '${_spec}' in '${_repo}'."
    return 1
  }
  printf '%s' "$_cands" | sed '/^$/d' | sort -V | tail -n1
}

_oci__validate_feature_tgz() {
  # @brief _oci__validate_feature_tgz <tgz> — Return 0 when `<tgz>` is a valid devcontainer feature artifact.
  #
  # A valid feature tarball must contain both `install.sh` and
  # `devcontainer-feature.json` at any depth. Strips leading path components and
  # dot-prefixed directory names to handle the various packing conventions used
  # by different OCI publishers.
  #
  # Args:
  #   <tgz>  Path to the `.tar.gz` feature artifact to validate.
  #
  # Returns: 0 if both required files are present, 1 otherwise.
  local _tgz="${1-}" _list
  [[ -f "$_tgz" ]] || {
    logging__error "feature tarball not found: '${_tgz}'."
    return 1
  }
  _list="$(tar -tzf "$_tgz" 2> /dev/null)" || {
    logging__error "failed to list contents of feature tarball '${_tgz}'."
    return 1
  }
  printf '%s\n' "$_list" | grep -Eq '(^|/)\.?/?install\.sh$' || {
    logging__error "feature tarball '${_tgz}' is missing install.sh."
    return 1
  }
  printf '%s\n' "$_list" | grep -Eq '(^|/)\.?/?devcontainer-feature\.json$' || {
    logging__error "feature tarball '${_tgz}' is missing devcontainer-feature.json."
    return 1
  }
}

_oci__expected_layer_digest_for_ref() {
  # @brief _oci__expected_layer_digest_for_ref <ref> — Fetch the OCI manifest for `<ref>` and return the digest of the first devcontainer layer.
  #
  # Fetches the manifest via `oras manifest fetch` and extracts the `digest`
  # field from the first layer whose `mediaType` matches one of the three
  # devcontainer layer media types. Returns 1 if the manifest cannot be fetched
  # or no matching layer is found.
  #
  # Args:
  #   <ref>  Full OCI reference (e.g. `ghcr.io/owner/repo:1.0.0`).
  #
  # Stdout: `sha256:<hex>` digest string.
  # Returns: 0 on success, 1 if the manifest is unavailable or has no matching layer.
  local _ref="${1-}" _manifest _dig _target _plain
  IFS=$'\t' read -r _target _plain <<< "$(_oci__normalize_target "$_ref")"
  _manifest="$(_oci__oras_capture "$_target" "$_plain" oras manifest fetch || true)"
  [[ -n "$_manifest" ]] || {
    logging__error "failed to fetch OCI manifest for '${_ref}'."
    return 1
  }
  _dig="$(printf '%s' "$_manifest" |
    json__query -r '
      [
        .layers[]?
        | select(.mediaType == "application/vnd.devcontainers.layer.v1+tar"
            or .mediaType == "application/vnd.devcontainers.layer.v1+tgz"
            or .mediaType == "application/vnd.oci.image.layer.v1.tar+gzip"
            or .mediaType == "application/vnd.oci.image.layer.v1.tar")
        | .digest
      ][0] // empty
    ' 2> /dev/null)" || _dig=""
  if [[ -z "$_dig" || "$_dig" == "null" ]]; then
    _dig="$(printf '%s\n' "$_manifest" | sed -n 's/.*"digest"[[:space:]]*:[[:space:]]*"\(sha256:[0-9a-fA-F]\{64\}\)".*/\1/p' | head -n1)"
  fi
  [[ -n "$_dig" && "$_dig" != "null" ]] || {
    logging__error "no devcontainer layer digest found in manifest for '${_ref}'."
    return 1
  }
  printf '%s\n' "$_dig"
}

oci__pull_feature_tgz() {
  # @brief oci__pull_feature_tgz <oci-ref> <dest-tgz> — Pull an OCI devcontainer feature artifact and write it as a `.tgz` file to `<dest-tgz>`.
  #
  # Validates that the pulled artifact contains `install.sh` and
  # `devcontainer-feature.json` before writing.
  #
  # Args:
  #   <oci-ref>   Full OCI image reference (e.g. `ghcr.io/owner/repo:tag`).
  #   <dest-tgz>  Destination path for the feature `.tgz` file.
  #
  # Returns: 0 on success, 1 on pull failure or invalid artifact shape.
  local _ref="${1-}" _dest="${2-}" _target _plain
  [[ -n "$_ref" && -n "$_dest" ]] || {
    logging__error "requires <oci-ref> and <dest-tgz>."
    return 1
  }
  oci__ensure_oras
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "'oras' is required but could not be set up."
    return "$_rc"
  }
  logging__download "Pulling OCI feature artifact '${_ref}'."
  _oci__ensure_auth_for "$_ref"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "OCI registry authentication failed for '${_ref}'."
    return "$_rc"
  }
  IFS=$'\t' read -r _target _plain <<< "$(_oci__normalize_target "$_ref")"
  local _tmp
  _tmp="$(file__mktmpdir "oci-pull")"
  local _expect_digest=""
  _expect_digest="$(_oci__expected_layer_digest_for_ref "$_ref" 2> /dev/null || true)"
  if ! _oci__oras_capture "$_target" "$_plain" oras pull -o "$_tmp" > /dev/null; then
    logging__error "failed to pull '${_ref}'."
    return 1
  fi
  local _tgz
  for _tgz in "$_tmp"/*.tgz; do
    [[ -f "$_tgz" ]] && break
  done
  [[ "${_tgz:-}" == "$_tmp/*.tgz" ]] && _tgz=""
  [[ -n "$_tgz" ]] || {
    logging__error "no .tgz layer materialized for '${_ref}'."
    return 1
  }
  _oci__validate_feature_tgz "$_tgz"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "feature artifact validation failed for '${_ref}'."
    return "$_rc"
  }
  if [[ -n "$_expect_digest" && "$_expect_digest" == sha256:* ]]; then
    local _got
    _got="sha256:$(verify__hash_file "$_tgz" 2> /dev/null || true)"
    if [[ "$_got" != "$_expect_digest" ]]; then
      logging__error "pulled layer digest mismatch for '${_ref}'."
      return 1
    fi
  fi
  cp "$_tgz" "$_dest" || {
    logging__error "failed to copy tgz artifact to '${_dest}'."
    return 1
  }
  return 0
}
