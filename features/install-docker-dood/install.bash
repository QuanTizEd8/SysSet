# shellcheck shell=bash
#
# install-docker-dood — Docker CLI + host-socket forwarding (Docker-outside-of-Docker).
#
# Installs only the client (no engine); the host daemon's socket is bind-mounted
# in and exposed to the container at build time (group setup) and container start
# (the entrypoint links or socat-proxies the socket).

# ---------------------------------------------------------------------------
# METHOD=auto resolver override — prefer package repos over the framework's
# binary-first default (security updates; consistent with install-docker).
# ---------------------------------------------------------------------------
# shellcheck disable=SC2329,SC2317
__resolve_method() {
  if users__is_privileged 2> /dev/null; then
    if [[ " ${_FEAT_CONTRACT_METHODS} " == *" upstream-package "* ]] &&
      ctx__match_when --quiet "${_FEAT_CONTRACT_UPSTREAM_PKG_WHEN}"; then
      printf 'upstream-package\n'
      return 0
    fi
    if [[ " ${_FEAT_CONTRACT_METHODS} " == *" package "* ]] &&
      ctx__match_when --quiet "${_FEAT_CONTRACT_PACKAGE_WHEN}"; then
      printf 'package\n'
      return 0
    fi
  fi
  printf 'binary\n'
}

# ---------------------------------------------------------------------------
# Ensure the `docker` group exists before users are added. The entrypoint may
# later realign its GID to the mounted socket's group at container start.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2329,SC2317
__install_finish_pre() {
  if users__is_privileged 2> /dev/null; then
    if ! users__group_exists docker; then
      logging__install "Creating 'docker' group."
      users__create_group docker || logging__warn "Could not create 'docker' group."
    fi
  fi
}

# shellcheck disable=SC2329,SC2317
__configure_user() {
  local _user="$1"
  users__group_exists docker || users__create_group docker || return 0
  logging__install "Adding user '${_user}' to the 'docker' group."
  users__add_to_group "${_user}" docker
}

# ---------------------------------------------------------------------------
# Post-install: CLI plugins (Buildx/Compose for the binary method, Compose
# Switch always when opted in). Best-effort; failures warn rather than abort.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  _docker_install_cli_plugins
}

_docker_install_cli_plugins() {
  case "${METHOD:-}" in
    upstream-package | package) _docker_install_plugin_pkgs ;;
    binary) _docker_install_plugin_bins ;;
  esac
  if [[ "${INSTALL_COMPOSE_SWITCH:-true}" == "true" ]]; then
    _docker_install_compose_switch
  fi
}

# Package-based plugin install, after the method install added (and kept) the
# Docker repo. The framework's option-gated deps run before the repo exists.
_docker_install_plugin_pkgs() {
  local _pm _plugin
  _pm="$(ospkg__pm_key 2> /dev/null || printf '')"
  local -a _pkgs=()
  [[ "${INSTALL_BUILDX:-true}" == "true" ]] && _pkgs+=("$(_docker_plugin_pkg buildx "${_pm}")")
  [[ "${INSTALL_COMPOSE:-true}" == "true" ]] && _pkgs+=("$(_docker_plugin_pkg compose "${_pm}")")
  [[ ${#_pkgs[@]} -gt 0 ]] || return 0
  local _manifest="packages:"$'\n'
  for _plugin in "${_pkgs[@]}"; do
    [[ -n "${_plugin}" ]] && _manifest+="  - ${_plugin}"$'\n'
  done
  logging__install "Installing Docker CLI plugin package(s): ${_pkgs[*]}."
  ospkg__run --manifest "${_manifest}" ||
    logging__warn "Failed to install one or more Docker CLI plugin packages."
}

_docker_plugin_pkg() {
  local _plugin="$1" _pm="$2"
  case "${_pm}" in
    apt | dnf | yum) printf 'docker-%s-plugin' "${_plugin}" ;;
    apk) printf 'docker-cli-%s' "${_plugin}" ;;
    *) printf 'docker-%s' "${_plugin}" ;;
  esac
}

_docker_install_plugin_bins() {
  file__mkdir /usr/libexec/docker/cli-plugins
  [[ "${INSTALL_BUILDX:-true}" == "true" ]] &&
    _docker_gh_plugin docker/buildx docker-buildx "buildx-{tag}.linux-$(os__release_arch --flavor go)"
  [[ "${INSTALL_COMPOSE:-true}" == "true" ]] &&
    _docker_gh_plugin docker/compose docker-compose "docker-compose-linux-$(os__arch)"
}

# _docker_gh_plugin <owner/repo> <plugin-name> <asset-template with {tag}>
_docker_gh_plugin() {
  local _repo="$1" _name="$2" _asset_tmpl="$3"
  local _plugin_dir="/usr/libexec/docker/cli-plugins"
  local _tag _asset
  _tag="$(github__latest_tag "${_repo}" 2> /dev/null)" || _tag=""
  [[ -n "${_tag}" ]] || {
    logging__warn "Could not resolve latest ${_repo} release; skipping '${_name}'."
    return 0
  }
  _asset="${_asset_tmpl//\{tag\}/${_tag}}"
  logging__install "Installing Docker plugin '${_name}' (${_repo} ${_tag})."
  github__install_release \
    --repo "${_repo}" \
    --tag "${_tag}" \
    --asset "${_asset}" \
    --binary-dest "${_plugin_dir}/${_name}" \
    --sha256 none 2> /dev/null ||
    logging__warn "Failed to install Docker plugin '${_name}' from ${_repo}."
}

_docker_install_compose_switch() {
  local _dest="/usr/local/bin/compose-switch"
  local _arch _asset _tag
  _arch="$(os__release_arch --flavor go)"
  # Compose Switch names its release binary like docker-compose (it is a
  # drop-in), e.g. docker-compose-linux-amd64 — not compose-switch-linux-*.
  _asset="docker-compose-linux-${_arch}"
  _tag="$(github__latest_tag docker/compose-switch 2> /dev/null)" || _tag=""
  [[ -n "${_tag}" ]] || {
    logging__warn "Could not resolve Compose Switch release; skipping."
    return 0
  }
  logging__install "Installing Compose Switch (${_tag})."
  github__install_release \
    --repo docker/compose-switch \
    --tag "${_tag}" \
    --asset "${_asset}" \
    --binary-dest "${_dest}" \
    --sha256 none 2> /dev/null || {
    logging__warn "Failed to install Compose Switch."
    return 0
  }
  file__ln -sf /usr/local/bin/compose-switch /usr/local/bin/docker-compose
}
