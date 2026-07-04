# shellcheck shell=bash

# Hooks
# =====

# shellcheck disable=SC2329,SC2317
__resolve_version() {
  # go.dev/dl has no GitHub/npm/cargo registry and no plain-text checksums
  # sidecar, only the JSON index above — none of the framework's built-in
  # resolution types apply, hence this hook. Uses the JSON's own "stable"
  # boolean rather than the generic hyphen-based prerelease heuristic, since
  # Go's own prerelease naming ("go1.27rc1") has no hyphen.
  local _json _spec="${VERSION:-stable}"
  _json="$(_go_dl_json)"
  if [[ "${_spec}" == "latest" ]]; then
    json__query -r '.[0].version | ltrimstr("go")' < "${_json}"
    return
  fi
  json__query -r '.[] | select(.stable == true) | .version | ltrimstr("go")' < "${_json}" |
    ver__resolve_from_list "${_spec}"
}

# shellcheck disable=SC2329,SC2317
__install_run_binary_pre() {
  # method=binary: look up this exact release's SHA256 from the cached JSON
  # index (no plain checksums sidecar exists to point --sidecar at) so the
  # template's __install_run_binary__ verifies the download via BINARY_SHA256.
  if [[ "$(ctx__get plat.libc 2> /dev/null)" == musl ]]; then
    logging__error "method=binary is not supported on musl-based Linux (official binaries are glibc-only)."
    logging__info "Use method=package (Alpine ships a native Go build) or method=source instead."
    return 1
  fi
  local _asset_uri _asset_name
  _asset_uri="$(ctx__expand_pattern "${BINARY_ASSET_URI}")"
  _asset_name="${_asset_uri%%\?*}"
  _asset_name="${_asset_name##*/}"
  local _json
  _json="$(_go_dl_json)"
  declare -g BINARY_SHA256
  # shellcheck disable=SC2016  # $v and $f are jq variables, not shell variables
  BINARY_SHA256="$(json__query -r \
    --arg v "go${VERSION}" --arg f "${_asset_name}" \
    '.[] | select(.version == $v) | .files[] | select(.filename == $f) | .sha256' \
    < "${_json}")"
  [[ -n "${BINARY_SHA256}" ]] || {
    logging__error "No SHA256 checksum found for '${_asset_name}' (go${VERSION}) in the go.dev/dl release index."
    return 1
  }
}

# shellcheck disable=SC2329,SC2317
__install_run_binary_post() {
  # The tarball's payload is a whole directory tree (bin/, pkg/, src/, ...)
  # under a literal top-level "go/" — not a single binary — so binary_src is
  # only used to satisfy the template's primary-bin placement; this hook copies
  # the full tree over it.
  file__mkdir "${_RESOLVED_PREFIX}"
  file__cp -a "${INSTALLER_DIR}/asset/go/." "${_RESOLVED_PREFIX}/"
  logging__success "Go ${VERSION} extracted to '${_RESOLVED_PREFIX}'."
}

# shellcheck disable=SC2329,SC2317
__install_run_source_pre() {
  # method=source: same checksum problem as method=binary, but the template's
  # source auto-impl has no BINARY_SHA256-style override point, only the
  # generic "#sha256=<hex>" URI-fragment convention (already handled by
  # uri__fetch_asset) — so append it to SOURCE_ASSET_URI ourselves.
  local _json _hex
  _json="$(_go_dl_json)"
  # shellcheck disable=SC2016  # $v is a jq variable, not a shell variable
  _hex="$(json__query -r \
    --arg v "go${VERSION}" \
    '.[] | select(.version == $v) | .files[] | select(.kind == "source") | .sha256' \
    < "${_json}")"
  [[ -n "${_hex}" ]] || {
    logging__error "No SHA256 checksum found for the go${VERSION} source tarball in the go.dev/dl release index."
    return 1
  }
  SOURCE_ASSET_URI="${SOURCE_ASSET_URI}#sha256=${_hex}"
}

# shellcheck disable=SC2329,SC2317
__install_run_source_build() {
  # Go's build (cmd/go, cmd/compile, ...) is itself written in Go, so it needs a
  # bootstrap compiler: the system Go package on musl (installed by
  # _dependencies.build.method-source there), or a freshly downloaded official
  # binary otherwise. CGO_ENABLED defaults to 0 (tool-ref.md's own
  # recommendation, notably for musl/Alpine) unless cgo_deps was requested.
  local _src_dir="$1" _bootstrap=""
  command -v go > /dev/null 2>&1 && _bootstrap="$(go env GOROOT 2> /dev/null || true)"
  if [[ -z "${_bootstrap}" ]]; then
    logging__info "No system Go found; bootstrapping from a freshly downloaded official release."
    _bootstrap="$(_go_fetch_bootstrap)" || return 1
  fi
  local _cgo=0
  [[ "${CGO_DEPS:-false}" == true ]] && _cgo=1
  logging__build "Building Go ${VERSION} from source (GOROOT_BOOTSTRAP='${_bootstrap}', CGO_ENABLED=${_cgo})."
  (
    cd "${_src_dir}/src" || exit 1
    export GOROOT_BOOTSTRAP="${_bootstrap}" CGO_ENABLED="${_cgo}"
    ./make.bash
  )
  local _rc=$?
  [[ -n "${_GO_BOOTSTRAP_TMP_DIR:-}" ]] && rm -rf "${_GO_BOOTSTRAP_TMP_DIR}"
  [[ $_rc == 0 ]] || {
    logging__error "Go source build failed (make.bash exited ${_rc})."
    return "$_rc"
  }
  file__mkdir "${_RESOLVED_PREFIX}"
  file__cp -a "${_src_dir}/." "${_RESOLVED_PREFIX}/"
  logging__success "Go ${VERSION} built from source and installed to '${_RESOLVED_PREFIX}'."
}

# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  _go_sync_goroot "export GOROOT=\"${_RESOLVED_PREFIX}\""
}

# shellcheck disable=SC2329,SC2317
__uninstall_finish_post() {
  _go_sync_goroot
}

# shellcheck disable=SC2329,SC2317
__configure_user() {
  # Custom GOPATH is opt-in (empty by default — Go's own $HOME/go default
  # already isolates per user with no configuration). When set, resolve and
  # persist it per configured user so isolation holds even when overridden.
  [[ -n "${GOPATH:-}" ]] || return 0
  local _user="$1" _resolved_gopath
  _resolved_gopath="$(users__expand_path --user "${_user}" "${GOPATH}")" || {
    logging__warn "Could not resolve gopath '${GOPATH}' for user '${_user}'; skipping."
    return 0
  }
  shell__sync_block \
    --files "$(shell__user_path_files --home "$(users__resolve_home "${_user}")")" \
    --marker "GOPATH (install-go)" \
    --content "export GOPATH=\"${_resolved_gopath}\""
  logging__install "Exported GOPATH='${_resolved_gopath}' for user '${_user}'."
}

# Private Functions
# =================

# shellcheck disable=SC2329,SC2317
_go_dl_json() {
  # Downloads (once per install run) and caches the full go.dev/dl release index.
  # Shared by __resolve_version and the binary/source checksum hooks below so the
  # ~350-release JSON document is only fetched once per run.
  if [[ -z "${_GO_DL_JSON_FILE:-}" || ! -s "${_GO_DL_JSON_FILE}" ]]; then
    file__mkdir "$INSTALLER_DIR"
    declare -g _GO_DL_JSON_FILE="${INSTALLER_DIR}/go-dl.json"
    logging__download "Fetching Go release index from 'go.dev/dl'."
    uri__fetch_asset "https://go.dev/dl/?mode=json&include=all" \
      --file-dest "${_GO_DL_JSON_FILE}" --sha256 none > /dev/null
  fi
  printf '%s\n' "${_GO_DL_JSON_FILE}"
}

# shellcheck disable=SC2329,SC2317
_go_fetch_bootstrap() {
  # Downloads a fresh official Go binary tarball to bootstrap a from-source
  # build on glibc systems, where _dependencies.build.method-source installs no
  # system Go package (see metadata.yaml — OS package repos structurally lag
  # Go's own bootstrap policy; confirmed empirically that Ubuntu 24.04's
  # golang-go, 1.22, cannot bootstrap building Go 1.26). Always bootstraps from
  # the latest stable release regardless of the version being built — well
  # within Go's N-2-major bootstrap policy for any realistically pinned target.
  # Sets _GO_BOOTSTRAP_TMP_DIR (for the caller to clean up) and prints the
  # bootstrap GOROOT path.
  local _json _boot_ver _boot_uri _boot_name _boot_hex
  _json="$(_go_dl_json)"
  _boot_ver="$(json__query -r '[.[] | select(.stable == true) | .version | ltrimstr("go")] | .[0]' < "${_json}")"
  [[ -n "${_boot_ver}" ]] || {
    logging__error "Could not determine a stable Go version to use as a bootstrap compiler."
    return 1
  }
  _boot_uri="$(ctx__expand_pattern "https://go.dev/dl/go${_boot_ver}.{plat.kernel:lower}-{plat.machine_go}.tar.gz")"
  _boot_name="${_boot_uri##*/}"
  # shellcheck disable=SC2016  # $v and $f are jq variables, not shell variables
  _boot_hex="$(json__query -r \
    --arg v "go${_boot_ver}" --arg f "${_boot_name}" \
    '.[] | select(.version == $v) | .files[] | select(.filename == $f) | .sha256' \
    < "${_json}")"
  [[ -n "${_boot_hex}" ]] || {
    logging__error "No SHA256 checksum found for bootstrap asset '${_boot_name}' (go${_boot_ver})."
    return 1
  }
  declare -g _GO_BOOTSTRAP_TMP_DIR
  _GO_BOOTSTRAP_TMP_DIR="$(file__mktmpdir install-go-bootstrap)"
  logging__download "Fetching bootstrap Go ${_boot_ver} from '${_boot_uri}'."
  uri__fetch_asset "${_boot_uri}" --sha256 "${_boot_hex}" --installer-dir "${_GO_BOOTSTRAP_TMP_DIR}" > /dev/null || {
    logging__error "Failed to download bootstrap Go ${_boot_ver}."
    rm -rf "${_GO_BOOTSTRAP_TMP_DIR}"
    return 1
  }
  printf '%s\n' "${_GO_BOOTSTRAP_TMP_DIR}/asset/go"
}

# shellcheck disable=SC2329,SC2317
_go_sync_goroot() {
  # GOROOT/GOPATH persistence.
  # GOROOT is only meaningful for binary/source (package method installs to a
  # distro-specific path outside our control; Go's own binary auto-detects its
  # GOROOT correctly there without our help).
  local _content="${1-}"
  local _has_content=false
  [[ $# -ge 1 ]] && _has_content=true
  [[ "${METHOD:-}" == "binary" || "${METHOD:-}" == "source" ]] || return 0
  local _files
  if users__is_user_path "${_RESOLVED_PREFIX}"; then
    _files="$(shell__user_path_files --home "$(users__home_of_path_owner "${_RESOLVED_PREFIX}")")"
  else
    _files="$(shell__system_path_files --profile_d "install-go-goroot.sh")"
  fi
  if [[ "${_has_content}" == true ]]; then
    shell__sync_block --files "${_files}" --marker "GOROOT (install-go)" --content "${_content}"
  else
    shell__sync_block --files "${_files}" --marker "GOROOT (install-go)"
  fi
}
