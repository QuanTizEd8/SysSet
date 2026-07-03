# shellcheck shell=bash
# GitHub Releases API: fetch JSON, resolve versions, select and download release assets.
#
# Fetches release metadata via the GitHub API, resolves version specs, selects
# platform-appropriate assets using arch/platform heuristics, downloads and
# verifies them, extracts archives, and installs binaries.
# Authenticates all API calls when possible: tries `gh auth token`, then
# `GITHUB_TOKEN`, then `GH_TOKEN` (see `_github__resolve_token`).

github__fetch_release_json() {
  # @brief github__fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>] — Fetch GitHub Releases API JSON for a repository.
  #
  # Without `--tag`: fetches `/releases/latest`. With `--tag`: fetches
  # `/releases/tags/<tag>`. Authenticates automatically when a token is
  # available (see `_github__resolve_token`).
  #
  # Args:
  #   <owner/repo>   GitHub repository in `owner/repo` format.
  #   --tag <tag>    Release tag to fetch (optional; defaults to latest).
  #   --dest <file>  Write JSON to this file instead of stdout (optional).
  #
  # Stdout: release JSON (suppressed when `--dest` is given).
  #
  # Returns: 0 on success, 1 on HTTP error or missing tool.
  local _repo="$1"
  shift
  local _tag="" _dest=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --dest)
        shift
        _dest="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  local _base _url
  _base="$(_github__api_base_url "$_repo")"
  if [ -n "$_tag" ]; then
    _url="${_base}/releases/tags/${_tag}"
  else
    _url="${_base}/releases/latest"
  fi

  _github__api_get "$_url" "$_dest"
  return $?
}

github__release_json_tag_name() {
  # @brief github__release_json_tag_name <file> — Print `tag_name` from a single-release JSON file (`/releases/latest` or `/releases/tags/...` response written to disk).
  #
  # Prefers jq (via `json__query`) for correct parsing on minified or pretty JSON.
  # Falls back to `grep -o` for `tag_name` only (first root `tag_name` key).
  #
  # Args:
  #   <file>  Path to a GitHub release JSON file.
  #
  # Stdout: tag name string (e.g. `v1.2.3`).
  #
  # Returns: 0 on success, 1 if unreadable or tag_name not found.
  local _f="$1"
  local _line
  [ -r "$_f" ] || {
    logging__error "release JSON file is not readable: '${_f}'."
    return 1
  }
  if _json__root_scalar_stdin tag_name < "$_f"; then
    return 0
  fi
  _line="$(grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$_f" | head -n 1)" || {
    logging__error "tag_name not found in release JSON '${_f}'."
    return 1
  }
  [ -n "$_line" ] || {
    logging__error "tag_name not found in release JSON '${_f}'."
    return 1
  }
  printf '%s\n' "$_line" | sed 's/^"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)"$/\1/'
}

github__release_json_id() {
  # @brief github__release_json_id <file> — Print the root release numeric `id` from a single-release JSON file.
  #
  # Uses jq (via `json__query`). Plain-text grep for the first `"id"` is unsafe on minified
  # responses where asset objects include `"id"` before the root release `id`.
  #
  # Args:
  #   <file>  Path to a GitHub release JSON file.
  #
  # Stdout: numeric release id.
  #
  # Returns: 0 on success, 1 if unreadable or id not found.
  local _f="$1"
  [ -r "$_f" ] || {
    logging__error "release JSON file is not readable: '${_f}'."
    return 1
  }
  json__root_scalar_stdin id < "$_f"
}

_github__release_json_digest_for_asset() {
  # @brief github__release_json_digest_for_asset <release.json> <asset_name> — Print lowercase hex SHA-256 from the GitHub Releases API asset `digest` field for the asset whose `name` equals `<asset_name>` exactly.
  #
  # Newer releases publish `digest` on each asset; older releases omit it — callers
  # should fall back to a downloaded `.sha256` sidecar when this returns 1.
  #
  # Args:
  #   <release.json>  Path to a `/releases/latest` or `/releases/tags/…` JSON file.
  #   <asset_name>    Exact `name` value of the release asset (e.g. `fzf-0.71.0-linux_amd64.tar.gz`).
  #
  # Stdout: 64-character lowercase hex digest.
  #
  # Returns: 0 on success, 1 if unreadable, unparsable, not found, or digest absent.
  local _f="$1" _name="$2" _out=""
  [ -r "$_f" ] || return 1
  [ -n "$_name" ] || return 1
  if ! bootstrap__jq; then return 1; fi
  # shellcheck disable=SC2016
  _out="$(json__query -r --arg n "$_name" '
      (.assets // [])[]
      | select(.name == $n)
      | .digest // empty
      | if length > 0 then (sub("^sha256:"; "") | ascii_downcase) else empty end
    ' "$_f" 2> /dev/null)" || _out=""
  [ -n "$_out" ] && [ "$_out" != "null" ] || return 1
  printf '%s\n' "$_out"
  return 0
}

github__release_json_digest_for_asset() {
  local _f="$1" _name="$2"
  [ -r "$_f" ] || {
    logging__error "release JSON file is not readable: '${_f}'."
    return 1
  }
  [ -n "$_name" ] || {
    logging__error "asset name is required."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read release asset digest."
    return "$_rc"
  }
  _github__release_json_digest_for_asset "$_f" "$_name"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "digest not found for asset '${_name}'."
    return "$_rc"
  }
}

github__release_json_digest_from_uri() {
  # @brief github__release_json_digest_from_uri <release-json-uri> <asset_name> — Fetch GitHub release JSON and print the asset SHA-256 digest.
  #
  # Fetches the release document at <release-json-uri> (typically
  # `https://api.github.com/repos/<owner>/<repo>/releases/tags/<tag>`) via the
  # GitHub API (authenticated when possible), then extracts the `digest` field for the
  # asset whose `name` equals <asset_name>.  Callers pass the result to
  # `install__release_asset` as `--sha256 <hex>`.
  #
  # Args:
  #   <release-json-uri>  Full GitHub Releases API URL for a single release.
  #   <asset_name>        Exact release asset filename.
  #
  # Stdout: 64-character lowercase hex digest.
  #
  # Returns: 0 on success, 1 if the fetch fails, the asset is not found, or digest is absent.
  local _uri="$1" _name="$2"
  local _reljson _digest=""
  [ -n "$_uri" ] && [ -n "$_name" ] || {
    logging__error "release JSON URI and asset name are required."
    return 1
  }
  _reljson="$(mktemp)"
  if _github__api_get "$_uri" "$_reljson" 2> /dev/null; then
    _digest="$(_github__release_json_digest_for_asset "$_reljson" "$_name")" || _digest=""
  fi
  rm -f "$_reljson"
  [ -n "$_digest" ] || {
    logging__error "digest not found for asset '${_name}' at '${_uri}'."
    return 1
  }
  printf '%s\n' "$_digest"
  return 0
}

github__fetch_release_asset_tarball() {
  # @brief github__fetch_release_asset_tarball <owner/repo> <tag> <asset-name> <dest-file> — Download a release asset and verify its SHA-256 if a digest is available in the API.
  #
  # The download URL is `https://github.com/<repo>/releases/download/<tag>/<asset-name>`.
  # Respects the same GitHub API auth as `github__fetch_release_json`.
  # Note: for new code prefer `github__install_release` which also handles
  # archive extraction and binary installation in addition to download+verify.
  #
  # Args:
  #   <owner/repo>   GitHub repository in "owner/repo" format.
  #   <tag>          Release tag (e.g. `v1.2.3`).
  #   <asset-name>   Exact asset filename (e.g. `fzf-0.71.0-linux_amd64.tar.gz`).
  #   <dest-file>    Destination path to write the downloaded file.
  #
  # Returns: 0 on success, 1 on download failure or SHA-256 mismatch.
  local _repo="$1" _tag="$2" _asset="$3" _dest="$4"
  local _rel _digest _url

  if [ -z "$_repo" ] || [ -z "$_tag" ] || [ -z "$_asset" ] || [ -z "$_dest" ]; then
    logging__error "need owner/repo, tag, asset, dest"
    return 1
  fi

  _rel="$(mktemp)"
  if github__fetch_release_json "$_repo" --tag "$_tag" --dest "$_rel" 2> /dev/null; then
    _digest="$(_github__release_json_digest_for_asset "$_rel" "$_asset")" || _digest=""
  else
    _digest=""
  fi
  rm -f "$_rel"

  _url="https://github.com/${_repo}/releases/download/${_tag}/${_asset}"

  if ! net__fetch_url_file "$_url" "$_dest"; then
    return 1
  fi

  if [ -n "$_digest" ] && [ "$_digest" != "null" ]; then
    if ! verify__sha "$_dest" "$_digest"; then
      return 1
    fi
  else
    logging__warn "No digest in release metadata for '${_asset}' — skipping verification."
  fi
  return 0
}

github__install_release() {
  # @brief github__install_release OPTIONS — Resolve a GitHub release asset and install via uri__fetch_asset.
  #
  # Resolves a release asset from the GitHub API, then delegates download,
  # verification, extraction, and installation to `install__release_asset`. When neither
  # `--asset` nor `--asset-regex` is given, `github__pick_release_asset` heuristics
  # select the best-matching asset for the current OS and architecture.
  #
  # Two automatic behaviors are applied before delegation:
  #
  # - **JSON digest**: the SHA-256 from the GitHub release API is passed as
  #   `--sha256` unless the caller already passes `--sha256` (any value). When
  #   `--sha256 none` is given, JSON lookup and digest verification are both
  #   skipped. When `--sha256 <hex>` is given, only that hash is used (no JSON
  #   fetch).
  # - **Sidecar auto-probe**: when `--sidecar` is not given, the following
  #   candidate URLs are probed in order: `<asset-url>.sha256`,
  #   `<release-base>/SHA256SUMS`, `<release-base>/sha256sum.txt`. A found
  #   sidecar is forwarded to `uri__fetch_asset`; none found → warn and continue.
  #
  # Args:
  #   --repo <owner/repo>     GitHub repository slug (e.g. `oras-project/oras`).
  #                           Required.
  #   --tag <tag>             Full release tag (e.g. `v1.2.3`). Required.
  #   --asset <name>          Exact asset filename; skips API enumeration and
  #                           heuristic selection. Mutually exclusive with
  #                           `--asset-regex`.
  #   --asset-regex <ere>     ERE pre-filter applied before
  #                           `github__pick_release_asset` heuristics. Mutually
  #                           exclusive with `--asset`.
  #
  # All options accepted by `uri__fetch_asset` (`--binary-src`, `--binary-dest`,
  # `--file-src`, `--file-dest`, `--chmod-exec`, `--installer-dir`, `--sha256`,
  # `--sidecar`, `--gpg-key`, `--gpg-sig`, `--header`, `--netrc-file`, `--filename`,
  # `--owner-group`, `--retry`) are accepted and forwarded unchanged.
  #
  # `--repo` and `--tag` are required.
  #
  # Stdout:
  #   - `--binary-dest` given: one absolute installed binary path per line, in
  #     `--binary-src` order (or auto-discovery order when N=0).
  #   - `--file-dest` given: one absolute installed file path per line, in
  #     `--file-src` order.
  #   - Both given: binary paths first, then file paths.
  #   - Neither given: the `work_dir/asset` directory path (one line).
  #
  # Returns: 0 on success, 1 on any failure.
  local _repo="" _tag="" _asset="" _asset_regex=""
  local _caller_sha256="" _caller_sha256_set=false
  local _caller_sidecar="" _caller_sidecar_set=false
  local _nbsrc=0 _nbdest=0
  local -a _passthrough=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        _repo="$2"
        shift 2
        ;;
      --tag)
        _tag="$2"
        shift 2
        ;;
      --asset)
        _asset="$2"
        shift 2
        ;;
      --asset-regex)
        _asset_regex="$2"
        shift 2
        ;;
      --sha256)
        _caller_sha256="$2"
        _caller_sha256_set=true
        _passthrough+=(--sha256 "$2")
        shift 2
        ;;
      --sidecar)
        _caller_sidecar_set=true
        _caller_sidecar="$2"
        shift 2
        ;;
      --binary-src)
        _nbsrc=$((_nbsrc + 1))
        _passthrough+=("$1" "$2")
        shift 2
        ;;
      --binary-dest)
        _nbdest=$((_nbdest + 1))
        _passthrough+=("$1" "$2")
        shift 2
        ;;
      --file-src | --file-dest | \
        --header | --netrc-file | --filename | --owner-group | \
        --installer-dir | --gpg-key | --gpg-sig | --retry | --chmod-exec)
        _passthrough+=("$1" "$2")
        shift 2
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  [[ -n "$_repo" && -n "$_tag" ]] || {
    logging__error "--repo and --tag are required."
    return 1
  }
  [[ -z "$_asset" || -z "$_asset_regex" ]] || {
    logging__error "--asset and --asset-regex are mutually exclusive."
    return 1
  }

  # Early-exit validations before any network I/O.
  if "$_caller_sha256_set" && [[ "$_caller_sha256" != "none" ]]; then
    [[ "$_caller_sha256" =~ ^[0-9a-fA-F]{64}$ ]] || {
      logging__error "--sha256 accepts a 64-char hex or 'none', got '${_caller_sha256}'."
      return 1
    }
  fi
  [[ "$_nbsrc" -gt 0 && "$_nbdest" -gt 1 && "$_nbsrc" -ne "$_nbdest" ]] && {
    logging__error "${_nbsrc} --binary-src but ${_nbdest} --binary-dest (must be equal or use 1 --binary-dest for all)."
    return 1
  }

  local _release_base="https://github.com/${_repo}/releases/download/${_tag}"

  # Resolve asset: explicit name, regex selection, or heuristic selection.
  if [[ -z "$_asset" ]]; then
    local _picked_url
    if [[ -n "$_asset_regex" ]]; then
      _picked_url="$(github__pick_release_asset "$_repo" --tag "$_tag" --asset-regex "$_asset_regex")"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to pick release asset for '${_repo}' (tag='${_tag}')."
        return "$_rc"
      }
    else
      _picked_url="$(github__pick_release_asset "$_repo" --tag "$_tag")"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to pick release asset for '${_repo}' (tag='${_tag}')."
        return "$_rc"
      }
    fi
    _asset="${_picked_url##*/}"
  fi

  # Pass sidecar through (relative name → install__release_asset resolves via release base).
  if "$_caller_sidecar_set"; then
    _passthrough+=(--sidecar "${_caller_sidecar}")
  fi

  local -a _sha256_args=()
  if ! "$_caller_sha256_set"; then
    local _json_digest=""
    _json_digest="$(github__release_json_digest_from_uri \
      "https://api.github.com/repos/${_repo}/releases/tags/${_tag}" "$_asset")" || _json_digest=""
    if [[ -n "$_json_digest" ]]; then
      _sha256_args=(--sha256 "$_json_digest")
    else
      logging__warn "no JSON digest for '${_asset}' — skipping JSON SHA-256."
    fi
  fi

  install__release_asset \
    --asset-uri "${_release_base}/${_asset}" \
    "${_sha256_args[@]}" \
    "${_passthrough[@]}"
}

github__latest_tag() {
  # @brief github__latest_tag <owner/repo> — Print the latest release tag name.
  #
  # Args:
  #   <owner/repo>  GitHub repository in "owner/repo" format.
  #
  # Stdout: the tag name (e.g. `v1.2.3`).
  #
  # Returns: 0 on success, 1 if the API call fails or the tag cannot be parsed.
  local _repo="$1"
  local _json="" _tag=""
  _json="$(github__fetch_release_json "$_repo")" || true
  if [ -n "$_json" ]; then
    _tag="$(printf '%s\n' "$_json" | _json__root_scalar_stdin tag_name)" || _tag=""
    if [ -z "$_tag" ]; then
      logging__debug "github__latest_tag: jq unavailable or parse failed — falling back to grep for tag_name."
      _tag="$(printf '%s\n' "$_json" |
        grep '"tag_name"' | head -1 |
        sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')" || _tag=""
    fi
  fi
  if [ -n "$_tag" ]; then
    echo "$_tag"
    return 0
  fi

  if [ -n "$_json" ]; then
    logging__error "could not parse tag_name from API response for '${_repo}'."
  fi

  # Fallback: resolve tag via the /releases/latest redirect on github.com.
  # Only applicable when _repo is an owner/repo slug (not a full API URL).
  local _fallback_tag="" _slug
  if [[ "$_repo" == https://* || "$_repo" == http://* ]]; then
    _slug="${_repo##*/repos/}"
  else
    _slug="$_repo"
  fi
  if [[ "$_slug" != *://* ]]; then
    _fallback_tag="$(
      net__fetch_url_stdout "https://github.com/${_slug}/releases/latest" |
        sed -n 's|.*href="/'"${_slug}"'/releases/tag/\([^"?#]*\)".*|\1|p' |
        head -1 || true
    )"
  fi

  if [ -n "$_fallback_tag" ]; then
    echo "$_fallback_tag"
    return 0
  fi

  logging__error "failed to resolve latest tag for '${_repo}' (GitHub API unreachable and redirect fallback failed)."
  return 1
}

github__release_tags() {
  # @brief github__release_tags <owner/repo> [--per_page N] [--all] [--retries N] [--retry-delay SEC>] — Print one release tag per line (newest first) from `/releases?per_page=N` (default 100).
  #
  # Useful for version-matching against a list (grep/sort/tail in the caller).
  # Without --all: fetches only the first page (up to --per_page tags). With
  # --all: walks `page=1,2,...` until a page returns fewer than --per_page
  # items (short-page termination — simpler than Link-header parsing and
  # correct for idempotent helpers).
  #
  # HTTP fetches already use curl retries (5xx, 429, etc.) via net__fetch_url_stdout;
  # --retries/--retry-delay add full end-to-end attempts when parsing fails or the
  # API returns an error payload after a successful HTTP status.
  #
  # Args:
  #   <owner/repo>       GitHub repository in "owner/repo" format.
  #   --per_page N       Releases per page to request (default: 100).
  #   --all              Paginate through every release (default: first page only).
  #   --retries N        Maximum attempts for the whole list operation (default: 1).
  #   --retry-delay SEC  Seconds to sleep between attempts (default: 4; ignored when N=1).
  #
  # Stdout: one tag name per line, newest first.
  local _repo="$1"
  shift
  local _per_page=100 _all=false _retries=1 _retry_delay=4
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --per_page)
        shift
        _per_page="$1"
        shift
        ;;
      --all)
        _all=true
        shift
        ;;
      --retries)
        shift
        _retries="$1"
        shift
        ;;
      --retry-delay)
        shift
        _retry_delay="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  case "$_retries" in '' | *[!0-9]*)
    logging__error "--retries must be a non-negative integer."
    return 1
    ;;
  esac
  [ "$_retries" -lt 1 ] && _retries=1
  case "$_retry_delay" in '' | *[!0-9]*)
    logging__error "--retry-delay must be a non-negative integer."
    return 1
    ;;
  esac

  local _base
  _base="$(_github__api_base_url "$_repo")"
  local _attempt=1
  while [ "$_attempt" -le "$_retries" ]; do
    if [ "$_all" = "false" ]; then
      local _url="${_base}/releases?per_page=${_per_page}"
      if _github__api_list_field "$_url" "tag_name"; then
        return 0
      fi
    else
      if _github__paginate_list_field \
        "${_base}/releases" \
        "tag_name" "$_per_page"; then
        return 0
      fi
    fi

    if [ "$_attempt" -ge "$_retries" ]; then
      logging__error "failed to reach GitHub API for '${_repo}' after ${_retries} attempt(s)."
      return 1
    fi
    logging__warn "GitHub API list failed for '${_repo}' (attempt ${_attempt}/${_retries}); retrying in ${_retry_delay}s."
    sleep "$_retry_delay"
    _attempt=$((_attempt + 1))
  done
}

github__resolve_version() {
  # @brief github__resolve_version <owner/repo> [<version-spec>] — Resolve a version spec to a release or tag, printing the full tag and bare version.
  #
  # Version specs:
  #   "stable" / ""  Latest non-prerelease release (releases API) or the newest tag
  #                  without a pre-release suffix (tags API fallback / --endpoint tag).
  #   "latest"       Most recently published release or tag, including pre-releases.
  #   "X"            Latest stable release/tag whose version starts with X.
  #   "X.Y"          Latest stable release/tag whose version starts with X.Y.
  #   "X.Y.Z"        Latest stable release/tag whose version starts with X.Y.Z
  #                  (resolves to X.Y.Z itself when no build suffix exists, or
  #                  the newest build e.g. X.Y.Z-1 when the repo uses them).
  #   "X.Y.Z-BUILD"  Prefix-matched: resolves to the newest X.Y.Z-BUILD* release/tag.
  #
  # Leading non-numeric characters are stripped from both the spec and each tag
  # before comparison, so "v1.2", "1.2", and "jq-1.2" are all equivalent specs.
  # Stable filtering for releases uses GitHub's authoritative prerelease/draft fields.
  # Stable filtering for tags uses a heuristic: tags whose bare version contains a
  # hyphen (e.g. "1.2.3-rc1") are treated as pre-releases.
  #
  # For partial specs, items are fetched page by page (newest first) and the
  # first matching result is returned; pagination stops as soon as a match
  # is found, so only as many API calls as necessary are made.
  #
  # Args:
  #   <owner/repo>     GitHub repository in "owner/repo" format.
  #   [<version-spec>] Version spec string (default: "stable").
  #   --tag            Print only the full tag (line 1).
  #   --version        Print only the bare version (line 2).
  #   --endpoint E     API to query: "release" (releases only), "tag" (tags only),
  #                    or "auto" (try releases first, fall back to tags; default).
  #   --tag-prefix P   Only consider releases/tags whose tag starts with P.
  #                    Required when the repo hosts multiple release lines under
  #                    different tag namespaces (e.g. "lib/" to match lib/1.2.3).
  #                    When set, "stable" and "latest" specs use paginated listing
  #                    instead of the /releases/latest single-call endpoint.
  #
  # Stdout:
  #   By default (neither or both flags given): two lines — full tag then bare version.
  #   --tag only:     one line — full tag (e.g. "v1.2.3", "jq-1.7.1").
  #   --version only: one line — bare version with tag prefix stripped (e.g. "1.2.3").
  #
  # Returns: 0 on success, 1 if no matching release or tag is found, or on API error.
  local _repo="$1"
  shift
  local _spec="stable" _spec_set=false _want_tag=false _want_version=false _endpoint="auto" _tag_prefix=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        _want_tag=true
        shift
        ;;
      --version)
        _want_version=true
        shift
        ;;
      --endpoint)
        shift
        case "$1" in
          release | tag | auto) _endpoint="$1" ;;
          *)
            logging__error "--endpoint must be 'release', 'tag', or 'auto'"
            return 1
            ;;
        esac
        shift
        ;;
      --tag-prefix)
        shift
        _tag_prefix="$1"
        shift
        ;;
      --*)
        logging__error "unknown option: '$1'"
        return 1
        ;;
      *)
        if [ "$_spec_set" = "false" ]; then
          _spec="$1"
          _spec_set=true
          shift
        else
          logging__error "unexpected positional argument: '$1'"
          return 1
        fi
        ;;
    esac
  done

  # Pre-compute the normalised spec once; only numeric specs use it.
  local _norm=""
  case "$_spec" in
    stable | "" | latest) ;;
    *)
      _norm="$(ver__extract_version --keep-suffix "$_spec")"
      [ -n "$_norm" ] || {
        logging__error "spec '${_spec}' contains no numeric version content."
        return 1
      }
      ;;
  esac

  local _api_base _tag="" _t _bare
  _api_base="$(_github__api_base_url "$_repo")"

  # ── Releases API ────────────────────────────────────────────────────────────
  if [ "$_endpoint" = "auto" ] || [ "$_endpoint" = "release" ]; then
    case "$_spec" in
      stable | "")
        if [ -n "$_tag_prefix" ]; then
          # /releases/latest can't be prefix-filtered; paginate instead.
          _tag="$(_github__first_release_matching "$_api_base" "" --tag-prefix "$_tag_prefix")" || _tag=""
        else
          # /releases/latest always returns the most recent non-prerelease, non-draft release.
          _tag="$(github__latest_tag "$_api_base")" || _tag=""
        fi
        ;;
      latest)
        if [ -n "$_tag_prefix" ]; then
          # ?per_page=1 can't be prefix-filtered; paginate including pre-releases.
          _tag="$(_github__first_release_matching "$_api_base" "" --tag-prefix "$_tag_prefix" --prerelease)" || _tag=""
        else
          # Most recently published release including pre-releases; per_page=1 avoids
          # fetching unnecessary data since we only need the first result.
          local _releases
          _releases="$(_github__api_list_field \
            "${_api_base}/releases?per_page=1" \
            "tag_name")" || _releases=""
          _tag="$(printf '%s\n' "$_releases" | head -1)"
        fi
        ;;
      *)
        # Numeric spec: stream releases page by page until the first matching
        # stable tag is found. Pagination stops as soon as a match is found.
        if [ -n "$_tag_prefix" ]; then
          _tag="$(_github__first_release_matching "$_api_base" "$_norm" --tag-prefix "$_tag_prefix")" || _tag=""
        else
          _tag="$(_github__first_release_matching "$_api_base" "$_norm")" || _tag=""
        fi
        ;;
    esac
  fi

  # ── Tags API (fallback for auto when releases returned nothing, or forced) ──
  if [ -z "$_tag" ] && { [ "$_endpoint" = "auto" ] || [ "$_endpoint" = "tag" ]; }; then
    case "$_spec" in
      stable | "")
        # Walk tags newest-first; the first tag whose bare version carries no
        # pre-release suffix ("-rc1", "-beta", etc.) is considered stable.
        # Process substitution: break exits the while loop without sending SIGPIPE
        # to github__tags (the child process substitution handles its own exit).
        _tag=""
        while IFS= read -r _t; do
          [ -n "$_tag_prefix" ] && [[ "$_t" != "${_tag_prefix}"* ]] && continue
          _bare="$(ver__extract_version --keep-suffix "$_t" 2> /dev/null || true)"
          case "$_bare" in
            "" | *-*) continue ;;
            *)
              _tag="$_t"
              break
              ;;
          esac
        done < <(github__tags "$_api_base" --all)
        ;;
      latest)
        # Tags are returned newest-first by GitHub; take the first one.
        # Process substitution: github__tags child handles its own exit without
        # sending SIGPIPE into this shell's pipefail context.
        if [ -n "$_tag_prefix" ]; then
          _tag=""
          while IFS= read -r _t; do
            [[ "$_t" == "${_tag_prefix}"* ]] || continue
            _tag="$_t"
            break
          done < <(github__tags "$_api_base")
        else
          IFS= read -r _tag < <(github__tags "$_api_base") || _tag=""
        fi
        ;;
      *)
        # Process substitution: ver__first_matching_prefix exits early after a
        # match; github__tags runs as a child and handles its own exit.
        if [ -n "$_tag_prefix" ]; then
          _tag="$(ver__first_matching_prefix "$_norm" < <(github__tags "$_api_base" --all | grep "^${_tag_prefix}"))" || _tag=""
        else
          _tag="$(ver__first_matching_prefix "$_norm" < <(github__tags "$_api_base" --all))" || _tag=""
        fi
        ;;
    esac
  fi

  [ -n "$_tag" ] || {
    case "$_endpoint" in
      release) logging__error "no release matching '${_spec}' found for '${_repo}'." ;;
      tag) logging__error "no tag matching '${_spec}' found for '${_repo}'." ;;
      *) logging__error "no release or tag matching '${_spec}' found for '${_repo}'." ;;
    esac
    return 1
  }

  if [ "$_want_tag" = "true" ] && [ "$_want_version" = "false" ]; then
    printf '%s\n' "$_tag"
  elif [ "$_want_version" = "true" ] && [ "$_want_tag" = "false" ]; then
    printf '%s\n' "$(ver__extract_version --keep-suffix "$_tag")"
  else
    printf '%s\n%s\n' "$_tag" "$(ver__extract_version --keep-suffix "$_tag")"
  fi
  return 0
}

github__tags() {
  # @brief github__tags <owner/repo> [--per_page N] [--all] — Print one tag per line from `/tags?per_page=N` (default 100). Includes lightweight tags not associated with a release.
  #
  # Unlike github__release_tags (which uses /releases), this endpoint includes
  # all git tags, including lightweight ones not associated with a release.
  # See github__release_tags for the --all semantics (page-until-short).
  #
  # Args:
  #   <owner/repo>   GitHub repository in "owner/repo" format.
  #   --per_page N   Tags per page to request (default: 100).
  #   --all          Paginate through every tag (default: first page only).
  #
  # Stdout: one tag name per line.
  local _repo="$1"
  shift
  local _per_page=100 _all=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --per_page)
        shift
        _per_page="$1"
        shift
        ;;
      --all)
        _all=true
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  local _base
  _base="$(_github__api_base_url "$_repo")"

  if [ "$_all" = "false" ]; then
    local _url="${_base}/tags?per_page=${_per_page}"
    _github__api_list_field "$_url" "name"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "failed to reach GitHub API for '${_repo}'."
      return "$_rc"
    }
    return 0
  fi

  _github__paginate_list_field \
    "${_base}/tags" \
    "name" "$_per_page"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to reach GitHub API for '${_repo}'."
    return "$_rc"
  }
  return 0
}

github__release_asset_urls() {
  # @brief github__release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere>] — Print `browser_download_url` values from a release. `--filter` applies an ERE grep to the URL list.
  #
  # Without --tag: uses /releases/latest. With --tag: uses
  # /releases/tags/<tag>. Exits 1 if the API call fails.
  #
  # Args:
  #   <owner/repo>    GitHub repository in "owner/repo" format.
  #   --tag <tag>     Release tag to query (optional; defaults to latest).
  #   --filter <ere>  ERE grep pattern applied to the URL list (optional).
  #
  # Stdout: one `browser_download_url` per line.
  local _repo="$1"
  shift
  local _tag="" _filter=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --filter)
        shift
        _filter="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  local _tmpfile
  _tmpfile="$(mktemp)"

  local _fetch_args=""
  [ -n "$_tag" ] && _fetch_args="--tag ${_tag}"

  # shellcheck disable=SC2086
  github__fetch_release_json "$_repo" ${_fetch_args} --dest "$_tmpfile"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    rm -f "$_tmpfile"
    return "$_rc"
  }

  local _urls
  _urls="$(json__object_array_field_lines_stdin assets browser_download_url < "$_tmpfile")" || _urls=""
  rm -f "$_tmpfile"

  if [ -n "$_filter" ]; then
    printf '%s\n' "$_urls" | grep -E "$_filter"
  else
    printf '%s\n' "$_urls"
  fi
  return 0
}

github__pick_release_asset() {
  # @brief github__pick_release_asset <owner/repo> [--tag <tag>] [--asset-regex <ERE>] — Select a single release asset URL using heuristic arch/platform filters.
  #
  # Designed for tools that do not publish checksums or have irregular naming
  # conventions. Prefer explicit URL construction with checksum verification
  # when the release naming is known and stable.
  #
  # Filter cascade (each stage is skipped if it would reduce candidates to zero):
  #   1. Negative: eliminate assets for other CPU architectures.
  #   2. Negative: eliminate assets for other platforms (Windows, macOS, Android).
  #   3. Negative: eliminate non-binary files (checksums, packages, certs, metadata).
  #   4. Positive tiebreaker: prefer assets that explicitly name the current arch.
  #   5. Positive tiebreaker: prefer statically linked / musl builds.
  #
  # Args:
  #   <owner/repo>         GitHub repository in "owner/repo" format.
  #   --tag <tag>          Release tag to use (optional; defaults to /releases/latest).
  #   --asset-regex <ERE>  Pre-filter applied before the cascade. Exactly one
  #                        match skips the cascade; zero matches returns 1.
  #
  # Stdout: exactly one URL. Returns 1 if no match or >1 candidates remain.
  local _repo="$1"
  shift
  local _tag="" _asset_regex=""
  local _raw_arch="" _kernel=""
  local _own_arch_re="" _bad_arch_re="" _bad_platform_re="" _bad_misc_re=""
  local _tag_arg="" _urls="" _tmp="" _count=0 _re="" _n=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --asset-regex)
        shift
        _asset_regex="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  # ── Fetch all asset URLs ──────────────────────────────────────────────────
  [ -n "$_tag" ] && _tag_arg="--tag $_tag"
  # shellcheck disable=SC2086
  _urls="$(github__release_asset_urls "$_repo" ${_tag_arg})"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to list release assets for '${_repo}'."
    return "$_rc"
  }
  if [ -z "$_urls" ]; then
    logging__error "no assets found for '${_repo}'."
    return 1
  fi

  # ── Apply caller-supplied regex pre-filter ────────────────────────────────
  if [ -n "$_asset_regex" ]; then
    _tmp="$(printf '%s\n' "$_urls" | grep -E "$_asset_regex")" || true
    if [ -z "$_tmp" ]; then
      logging__error "--asset-regex '${_asset_regex}' matched no assets for '${_repo}'."
      return 1
    fi
    _urls="$_tmp"
    _count="$(printf '%s\n' "$_urls" | grep -c '.')"
    if [ "$_count" -eq 1 ]; then
      printf '%s\n' "$_urls"
      return 0
    fi
  fi

  # ── Build arch regex sets ─────────────────────────────────────────────────
  _raw_arch="$(os__arch)"
  case "$_raw_arch" in
    x86_64)
      _own_arch_re='[Aa]md64|x64|x86[_-]64'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]rm32|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    aarch64 | arm64)
      _own_arch_re='[Aa]arch64|[Aa]rm64'
      _bad_arch_re='[Aa]md64|x86[_-]64|-x64|_x64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    armv7l | armv7)
      _own_arch_re='[Aa][Rr][Mm]v7|[Aa][Rr][Mm]hf'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa]md64|x86[_-]64|-x64|_x64|[Aa][Rr][Mm]v[56]|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    armv6l | armv6)
      _own_arch_re='[Aa][Rr][Mm]v6'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa]md64|x86[_-]64|-x64|_x64|[Aa][Rr][Mm]v[57]|[Aa][Rr][Mm]hf|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    i386 | i686)
      _own_arch_re='i[36]86|-386|-686'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|ppc64|[Ss]390|riscv'
      ;;
    ppc64 | ppc64le)
      _own_arch_re='ppc64'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|i[36]86|-386|_386|[Ss]390|riscv'
      ;;
    s390 | s390x)
      _own_arch_re='[Ss]390'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|i[36]86|-386|_386|ppc64|riscv'
      ;;
    riscv64)
      _own_arch_re='riscv'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|i[36]86|-386|_386|ppc64|[Ss]390'
      ;;
  esac

  # ── Build platform regex sets ─────────────────────────────────────────────
  _kernel="$(os__kernel)"
  case "$_kernel" in
    Linux)
      _bad_platform_re='[Ww]indows|[Ww]in32|-win-|\.msi$|\.exe$|[Mm]ac[Oo][Ss]|-osx-|_osx_|[Dd]arwin|\.dmg$|[Aa]ndroid'
      ;;
    Darwin)
      _bad_platform_re='[Ww]indows|[Ww]in32|-win-|\.msi$|\.exe$|[Ll]inux|[Aa]ndroid'
      ;;
    *)
      _bad_platform_re='[Ww]indows|[Ww]in32|\.msi$|\.exe$|[Aa]ndroid'
      ;;
  esac

  # Packages, checksums, signatures, certificates, metadata.
  _bad_misc_re='\.deb$|\.rpm$|\.pkg$|\.apk$|\.[Aa]pp[Ii]mage$|\.snap$|[Cc]hecksums|sha256|sha512|\.sha1$|\.md5$|\.sig$|\.txt$|\.pub$|\.pem$|\.crt$|\.asc$|\.json$|\.sbom$'

  # ── Apply negative filters ────────────────────────────────────────────────
  # Each filter is skipped (not applied) when it would empty the candidate list.
  for _re in "$_bad_arch_re" "$_bad_platform_re" "$_bad_misc_re"; do
    [ -z "$_re" ] && continue
    _tmp="$(printf '%s\n' "$_urls" | grep -vE "$_re")" || true
    [ -n "$_tmp" ] && _urls="$_tmp"
  done

  # ── Apply positive tiebreakers ────────────────────────────────────────────
  # Each tiebreaker is skipped when it would empty the candidate list.
  for _re in "$_own_arch_re" 'static|musl'; do
    [ -z "$_re" ] && continue
    _tmp="$(printf '%s\n' "$_urls" | grep -E "$_re")" || true
    [ -n "$_tmp" ] && _urls="$_tmp"
  done

  # ── Count survivors and return ────────────────────────────────────────────
  _count="$(printf '%s\n' "$_urls" | grep -c '.')" || _count=0
  case "$_count" in
    1)
      printf '%s\n' "$_urls"
      return 0
      ;;
    0)
      logging__error "no matching asset for '${_repo}' (arch=${_raw_arch}, kernel=${_kernel})."
      return 1
      ;;
    *)
      logging__error "${_count} ambiguous assets remain for '${_repo}'; pass --asset-regex to disambiguate:"
      local _n
      while IFS= read -r _n; do
        logging__error "   ${_n}"
      done < <(printf '%s\n' "$_urls" | sed 's|.*/||')
      return 1
      ;;
  esac
}

_github__api_list_field() {
  # _github__api_list_field <url> <field>  (internal)
  #
  # Fetches a GitHub API list endpoint and extracts all values of the named JSON
  # field from each top-level array element, printing one value per line.
  # Returns 1 if the API call fails or the response is empty.
  #
  # Prefers jq then python3 (correct on minified one-line arrays and avoids nested
  # "name"/"tag_name" keys inside objects). Falls back to grep -o when neither is
  # available.
  local _url="$1"
  local _field="$2"
  local _json _lines _msg
  _json="$(_github__api_get "$_url")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "GitHub API request failed for '${_url}'."
    return "$_rc"
  }
  [ -z "$_json" ] && {
    logging__error "GitHub API returned empty response for '${_url}'."
    return 1
  }

  if printf '%s\n' "$_json" | json__query -e 'type == "object" and (.message | type == "string")' > /dev/null 2>&1; then
    _msg="$(printf '%s\n' "$_json" | json__query -r '.message // empty' 2> /dev/null)" || _msg=""
    logging__error "GitHub API error for '${_url}': ${_msg}"
    return 1
  fi

  _lines="$(printf '%s\n' "$_json" | json__array_field_lines_stdin "$_field")" || _lines=""
  if [ -n "$_lines" ]; then
    printf '%s\n' "$_lines"
    return 0
  fi

  if printf '%s\n' "$_json" | json__query -e 'type == "array" and length == 0' > /dev/null 2>&1; then
    logging__error "GitHub API returned an empty JSON array for '${_url}'."
    return 1
  fi

  logging__error "no '${_field}' values extracted from GitHub API response for '${_url}' (expected a non-empty JSON array of objects)."
  return 1
}

_github__paginate_list_field() {
  # _github__paginate_list_field <base_url> <field> <per_page>  (internal)
  #
  # Walks pages 1..N of a GitHub list endpoint (one that accepts `page=` and
  # `per_page=`), extracting <field> from every array element, until a page
  # returns fewer than <per_page> items (short-page termination). Prints every
  # extracted value on stdout. Returns 0 when at least one value was printed,
  # 1 when the first page fails to fetch (same contract as
  # _github__api_list_field for the single-page case).
  #
  # Args:
  #   <base_url>  API URL without the page/per_page query string.
  #   <field>     JSON field to extract from each array element.
  #   <per_page>  Page size; also the short-page threshold.
  local _base="$1"
  local _field="$2"
  local _per_page="$3"
  local _page=1 _json _count _got_any=false

  while :; do
    local _sep='?'
    case "$_base" in *\?*) _sep='&' ;; esac
    local _url="${_base}${_sep}per_page=${_per_page}&page=${_page}"
    _json="$(_github__api_get "$_url")"
    local _rc=$?
    if [[ $_rc != 0 ]]; then
      [[ "$_got_any" == "true" ]] && return 0
      return "$_rc"
    fi
    if [ -z "$_json" ]; then
      [ "$_got_any" = "true" ] && return 0
      return 1
    fi
    local _values
    _values="$(printf '%s\n' "$_json" | json__array_field_lines_stdin "$_field")" || _values=""
    if [ -n "$_values" ]; then
      printf '%s\n' "$_values"
      _got_any=true
    fi
    # Count items on this page to decide whether to continue. We count the
    # top-level array length (not the extracted field count) so that objects
    # missing the requested field don't trigger false-positive short-page
    # termination.
    _count="$(printf '%s\n' "$_json" | _github__count_top_level_array)" || _count=0
    [ -z "$_count" ] && _count=0
    if [ "$_count" -lt "$_per_page" ]; then
      [ "$_got_any" = "true" ] && return 0
      return 1
    fi
    _page=$((_page + 1))
  done
}

_github__count_top_level_array() {
  # _github__count_top_level_array  (internal)
  #
  # Reads a JSON array on stdin and prints its top-level element count.
  # Uses jq (via json__query); falls back to a best-effort `grep -c '^{'`-style
  # heuristic if jq cannot be installed.
  local _json
  _json="$(cat)"
  if printf '%s' "$_json" | json__query 'length' 2> /dev/null; then
    return 0
  fi
  # Fallback: count occurrences of top-level object open-brace. This is a
  # best-effort heuristic. Over-counts are harmless — the loop just runs an
  # extra empty page before terminating.
  printf '%s\n' "$_json" | grep -c '^[[:space:]]*{' || true
}

_github__escape_ere() {
  # _github__escape_ere <str>  (internal)
  #
  # Prints <str> with regex meta-characters escaped so it can be safely used
  # as a literal prefix/substring inside `grep` / `grep -E` patterns. Covers
  # both BRE and ERE metacharacters.

  # Chars escaped: \ . ^ $ * + ? ( ) { } | [ ]
  # ']' must come first inside the bracket expression; '\\' is escaped as
  # '\\\\' in the sed replacement to produce a single backslash.
  printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'
}

_github__api_base_url() {
  # _github__api_base_url <repo-or-url>  (internal)
  #
  # Normalises the first argument to a full GitHub API base URL.
  # If the argument already starts with http:// or https://, it is returned as-is.
  # Otherwise it is treated as an `owner/repo` slug and expanded to
  # `https://api.github.com/repos/<owner/repo>`.
  local _in="$1"
  if [[ "$_in" == https://* || "$_in" == http://* ]]; then
    printf '%s' "$_in"
  else
    printf 'https://api.github.com/repos/%s' "$_in"
  fi
}

_github__resolve_token() {
  # _github__resolve_token  (internal)
  #
  # Resolves a GitHub API token, tried in order: `gh auth token` (reuses an
  # already-authenticated gh CLI without duplicating its credential storage),
  # then $GITHUB_TOKEN, then $GH_TOKEN (both widely used by CI runners, e.g.
  # GitHub Actions sets GITHUB_TOKEN, other tools set GH_TOKEN). Sets the
  # global _GITHUB__TOKEN as a side effect rather than printing to stdout, so
  # callers must invoke it directly (not via command substitution) — running
  # it inside `$(...)` would resolve the token in a throwaway subshell and
  # silently discard it.
  _GITHUB__TOKEN=""
  if command -v gh > /dev/null 2>&1; then
    _GITHUB__TOKEN="$(gh auth token 2> /dev/null)" || _GITHUB__TOKEN=""
  fi
  [ -n "$_GITHUB__TOKEN" ] || _GITHUB__TOKEN="${GITHUB_TOKEN:-}"
  [ -n "$_GITHUB__TOKEN" ] || _GITHUB__TOKEN="${GH_TOKEN:-}"

  if [ -n "$_GITHUB__TOKEN" ]; then
    # logging.bash only masks $GITHUB_TOKEN eagerly at startup; a token from
    # `gh auth token` or $GH_TOKEN needs masking here so it can never appear
    # in LOG_FILE regardless of source.
    logging__mask_secret "$_GITHUB__TOKEN"
  else
    logging__info "No GitHub API token found ('gh auth token', \$GITHUB_TOKEN, \$GH_TOKEN all empty/unavailable); unauthenticated requests are capped at 60/hour by GitHub. Set \$GITHUB_TOKEN (or run 'gh auth login') to raise the limit."
  fi
}

_github__api_get() {
  # _github__api_get <url> [<dest_file>]  (internal)
  #
  # Performs a GitHub API GET with standard Accept/version headers and an
  # optional Authorization header from `_github__resolve_token` (gh CLI /
  # GITHUB_TOKEN / GH_TOKEN).
  # Suppresses xtrace around the authenticated call to prevent token leaking in
  # CI logs.  Passes output to stdout or to <dest_file> when provided.
  local _url="$1"
  local _dest="${2:-}"
  local _xt=false
  case "$-" in *x*) _xt=true ;; esac
  { set +x; } 2> /dev/null

  _github__resolve_token

  # Use set -- to accumulate --header args (POSIX alternative to arrays).
  set -- \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --header "User-Agent: devfeats"
  [ -n "$_GITHUB__TOKEN" ] && set -- "$@" --header "Authorization: Bearer ${_GITHUB__TOKEN}"

  local _ec=0
  if [ -n "$_dest" ]; then
    net__fetch_url_file "$_url" "$_dest" "$@" || _ec=$?
  else
    net__fetch_url_stdout "$_url" "$@" || _ec=$?
  fi
  [ "$_xt" = "true" ] && { set -x; } 2> /dev/null
  return "$_ec"
}

_github__first_release_matching() {
  # _github__first_release_matching <api_base> <norm_spec> [--tag-prefix P] [--prerelease]  (internal)
  #
  # Fetches releases page by page (newest first), returning the full tag of the
  # first matching release.  By default only stable (non-prerelease, non-draft)
  # releases are considered.  Pagination stops as soon as a match is found.
  #
  # Args:
  #   <api_base>      Full GitHub API base URL.
  #   <norm_spec>     Normalised version spec to match against (empty = any version).
  #   --tag-prefix P  Only consider releases whose tag_name starts with P.
  #   --prerelease    Include pre-releases (default: stable only).
  #
  # Stdout: the matched full release tag.
  # Returns: 0 on match, 1 if no match found or on API error.
  local _api_base="$1" _norm="$2"
  shift 2
  local _tag_prefix="" _prerelease=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag-prefix)
        shift
        _tag_prefix="$1"
        shift
        ;;
      --prerelease)
        _prerelease=true
        shift
        ;;
      *)
        logging__error "_github__first_release_matching: unknown option: '$1'"
        return 1
        ;;
    esac
  done
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to match GitHub release tags."
    return "$_rc"
  }
  local _jq_filter _per_page=100 _page=1 _json _tags _count _tag
  if [ "$_prerelease" = "true" ]; then
    _jq_filter='.[] | .tag_name'
  else
    _jq_filter='.[] | select(.prerelease == false and .draft == false) | .tag_name'
  fi

  while :; do
    local _url="${_api_base}/releases?per_page=${_per_page}&page=${_page}"
    _json="$(_github__api_get "$_url")"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "GitHub API request failed for '${_url}'."
      return "$_rc"
    }

    _tags="$(printf '%s\n' "$_json" | json__query -r "$_jq_filter" 2> /dev/null)" || _tags=""

    if [ -n "$_tag_prefix" ] && [ -n "$_tags" ]; then
      _tags="$(printf '%s\n' "$_tags" | grep "^${_tag_prefix}")" || _tags=""
    fi

    if [ -n "$_tags" ]; then
      if [ -z "$_norm" ]; then
        # No version spec: return the first (newest) matching tag.
        printf '%s\n' "$_tags" | head -1
        return 0
      elif _tag="$(printf '%s\n' "$_tags" | ver__first_matching_prefix "$_norm")"; then
        printf '%s\n' "$_tag"
        return 0
      fi
    fi

    _count="$(printf '%s\n' "$_json" | _github__count_top_level_array)" || _count=0
    [ -z "$_count" ] && _count=0
    [ "$_count" -lt "$_per_page" ] && return 1

    _page=$((_page + 1))
  done
}
