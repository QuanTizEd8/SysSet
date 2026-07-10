# shellcheck shell=bash
# crates.io registry API: fetch crate metadata and resolve version specs.
#
# Fetches the crate document via the crates.io API and resolves version specs
# (including "stable", "latest", semver prefixes, and exact versions) against
# the published, non-yanked version list.
# crates.io rejects requests without a descriptive User-Agent header (HTTP 403
# per its API data-access policy), so every registry call sets one explicitly.

cargo__resolve_version_uri() {
  # @brief cargo__resolve_version_uri <uri> [<spec>] — Resolve a version spec using the crates.io crate document at <uri>.
  #
  # Fetches the crate document JSON from <uri> (any URI scheme supported by
  # net__fetch_url_stdout; typically the crates.io crate endpoint
  # https://crates.io/api/v1/crates/<crate>), builds a newest-first list of the
  # crate's published, non-yanked versions (`.versions[].num` where
  # `.yanked != true`), and resolves the spec via ver__resolve_from_list.
  # crates.io returns versions in publish order (not version order), so the list
  # is sorted explicitly before resolution.
  #
  # Version specs (delegated to ver__resolve_from_list):
  #   "stable" / ""  Newest final (non-prerelease) published version.
  #   "latest"       Newest published version, including pre-releases.
  #   starts with a digit (e.g. "1", "1.2", "1.2.3")
  #                  Newest final version whose bare version matches the prefix,
  #                  with exact matches taking priority (e.g. "1.2" → "1.2").
  #
  # crates.io requires a descriptive User-Agent header (returns HTTP 403
  # otherwise); _cargo__registry_get sets one automatically.
  #
  # Args:
  #   <uri>    Full URI of the crates.io crate document (required).
  #   [<spec>] Version spec string (default: "stable").
  #
  # Stdout: exact bare version string (e.g. `1.2.3`).
  #
  # Returns: 0 on success, 1 if no matching version found or on API error.
  local _uri="$1"
  local _spec="${2:-stable}"

  [ -n "$_uri" ] || {
    logging__error "uri is required."
    return 1
  }

  local _json
  _json="$(_cargo__registry_get "$_uri")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to fetch crate document from '${_uri}'."
    return "$_rc"
  }
  [ -n "$_json" ] || {
    logging__error "empty response from '${_uri}'."
    return 1
  }

  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to resolve crate versions."
    return "$_rc"
  }

  # Build a newest-first list of non-yanked versions. `.versions[]?` tolerates a
  # missing 'versions' key; `select(.yanked != true)` drops yanked releases
  # (a yanked version's 'yanked' field is true, otherwise false).
  local _versions
  _versions="$(printf '%s\n' "$_json" |
    json__query -r '.versions[]? | select(.yanked != true) | .num' 2> /dev/null |
    sort -rV)" || _versions=""
  [ -n "$_versions" ] || {
    logging__error "no non-yanked versions found in crate document at '${_uri}'."
    return 1
  }

  local _version
  _version="$(printf '%s\n' "$_versions" | ver__resolve_from_list "$_spec")" || {
    logging__error "no version matching '${_spec}' at '${_uri}'."
    return 1
  }
  printf '%s\n' "$_version"
  return 0
}

_cargo__registry_get() {
  # _cargo__registry_get <url> [<dest_file>]  (internal)
  #
  # Performs a crates.io API GET. crates.io returns HTTP 403 for requests that
  # do not carry a descriptive User-Agent header (its API data-access policy),
  # so one is always set, along with an Accept: application/json header.
  # Writes to <dest_file> when given, otherwise to stdout.
  local _url="$1"
  local _dest="${2:-}"
  # Use set -- to accumulate --header args (mirrors _npm__registry_get).
  set -- --header "Accept: application/json" --header "User-Agent: devfeats"
  if [ -n "$_dest" ]; then
    net__fetch_url_file "$_url" "$_dest" "$@"
  else
    net__fetch_url_stdout "$_url" "$@"
  fi
}
