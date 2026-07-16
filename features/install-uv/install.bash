# shellcheck shell=bash

# Fetch (once per install run) the cargo-dist version that actually built the
# resolved uv release, from the release's own dist-manifest.json asset (e.g.
# https://github.com/astral-sh/uv/releases/download/0.9.7/dist-manifest.json
# → "dist_version": "0.30.1"). This value is NOT constant across uv releases
# (confirmed empirically to differ from ruff's cargo-dist version, and to vary
# release-to-release) so it must never be hardcoded. Memoized in _UV_DIST_VERSION
# via `declare -g` since __configure_user runs once per configured user and this
# only needs to be fetched once.
# shellcheck disable=SC2329,SC2317
__fetch_uv_dist_version() {
  [[ -v _UV_DIST_VERSION ]] && return 0
  declare -g _UV_DIST_VERSION=""
  [[ -n "${_FEAT_RESOLVED_TAG:-}" ]] || return 0
  # Capped retries: a specific, correct asset URL, so a 404 may be a brief
  # propagation blip worth riding out (~15s), but must not stall the install on
  # the default ~5-min budget if the asset is genuinely absent (older release).
  _UV_DIST_VERSION="$(net__fetch_url_stdout \
    "https://github.com/astral-sh/uv/releases/download/${_FEAT_RESOLVED_TAG}/dist-manifest.json" \
    --retries 4 --delay 5 \
    2> /dev/null | json__root_scalar_stdin dist_version 2> /dev/null)" || _UV_DIST_VERSION=""
  [[ -n "${_UV_DIST_VERSION}" ]] || logging__warn "Could not determine the cargo-dist version that built uv ${_FEAT_RESOLVED_TAG}; 'provider.version' will be empty in the uv receipt."
}

# Write the cargo-dist receipt that `uv self update` requires. uv reads it from
# ${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv-receipt.json and uses install_prefix
# to locate the binary when writing the update.
# Only applies to method=binary: the receipt claims a github/cargo-dist-sourced
# flat install at PREFIX/bin, which is only accurate for that method. Package
# and cargo installs have their own PM-managed locations and must not be
# described by this receipt (and `uv self update` explicitly refuses to run for
# non-standalone installs anyway).
# shellcheck disable=SC2329,SC2317
__configure_user() {
  [[ "${METHOD:-}" == "binary" ]] || {
    logging__skip "METHOD='${METHOD:-unset}' is not 'binary'; skipping uv receipt."
    return 0
  }
  local _user="$1"
  local _xdg_config
  # shellcheck disable=SC2016
  _xdg_config="$(users__expand_path --user "$_user" '${XDG_CONFIG_HOME:-${HOME}/.config}')" || {
    logging__warn "Could not resolve XDG_CONFIG_HOME for '${_user}'; skipping uv receipt."
    return 0
  }
  __fetch_uv_dist_version
  local _receipt_dir="${_xdg_config}/uv"
  local _receipt_path="${_receipt_dir}/uv-receipt.json"
  file__mkdir "${_receipt_dir}"
  printf '%s\n' \
    "{\"binaries\":[\"uv\",\"uvx\"],\"binary_aliases\":{},\"cdylibs\":[],\"cstaticlibs\":[],\"install_layout\":\"flat\",\"install_prefix\":\"${_RESOLVED_PREFIX}/bin\",\"modify_path\":false,\"provider\":{\"source\":\"cargo-dist\",\"version\":\"${_UV_DIST_VERSION}\"},\"source\":{\"app_name\":\"uv\",\"name\":\"uv\",\"owner\":\"astral-sh\",\"release_type\":\"github\"},\"version\":\"${VERSION:-}\"}" \
    > "${_receipt_path}"
  file__chown "${_user}:${_user}" "${_receipt_dir}" "${_receipt_path}" 2> /dev/null || true
  logging__install "Wrote uv self-update receipt → ${_receipt_path}"
}
