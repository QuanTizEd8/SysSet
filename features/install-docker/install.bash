# shellcheck shell=bash
#
# install-docker — host + Docker-in-Docker engine installer.
#
# The template drives the package/binary install; these hooks add the parts the
# generic machinery does not cover:
#   - __resolve_method    : prefer package repos over the framework's binary-first
#                           auto default (a daemon needs a systemd unit + updates).
#   - __install_finish_pre: ensure the `docker` group exists before users are added.
#   - __install_finish_post: daemon.json, DinD containerd/iptables config, binary-
#                           method systemd units, CLI plugins, and host service.
#   - __configure_user    : add each resolved user to the `docker` group.

# ---------------------------------------------------------------------------
# Effective installation mode: host | dind.
# `auto` resolves to dind during a devcontainer build, host otherwise.
# ---------------------------------------------------------------------------
_docker_effective_mode() {
  case "${MODE:-auto}" in
    host | dind) printf '%s' "${MODE}" ;;
    *)
      if os__is_devcontainer_build; then printf 'dind'; else printf 'host'; fi
      ;;
  esac
}

# Return 0 when systemd is the active system init (so `systemctl` can manage
# services). False inside typical containers, which lack /run/systemd/system.
_docker_systemd_active() {
  command -v systemctl > /dev/null 2>&1 || return 1
  [[ -d /run/systemd/system ]] || return 1
  return 0
}

# ---------------------------------------------------------------------------
# METHOD=auto resolver override.
#
# The framework's __resolve_auto_method__ tries `binary` first, which for a
# system daemon is wrong: Docker's static tarball ships no systemd unit and no
# automatic security updates, and upstream recommends the package manager. So we
# prefer the repo/package methods and fall back to the static binary only when no
# repository covers the platform.
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
# Ensure the `docker` group exists before configure_users adds members.
# Package installs create it via postinst; the binary method does not.
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

# ---------------------------------------------------------------------------
# Per-user configuration: grant Docker access via the `docker` group.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2329,SC2317
__configure_user() {
  local _user="$1"
  users__group_exists docker || users__create_group docker || return 0
  logging__install "Adding user '${_user}' to the 'docker' group."
  users__add_to_group "${_user}" docker
}

# ---------------------------------------------------------------------------
# Post-install: daemon config, DinD runtime prep, plugins, host service.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  local _mode
  _mode="$(_docker_effective_mode)"
  logging__info "Finalizing Docker install (mode='${_mode}', method='${METHOD:-unset}')."

  _docker_write_daemon_json
  _docker_install_cli_plugins

  if [[ "${_mode}" == "dind" ]]; then
    _docker_write_containerd_config
    _docker_select_iptables
  fi

  if [[ "${METHOD:-}" == "binary" && "${_mode}" == "host" ]]; then
    _docker_write_systemd_units
  fi

  if [[ "${_mode}" == "host" ]]; then
    _docker_enable_service
  fi

  logging__success "Docker install finalized."
}

# ---------------------------------------------------------------------------
# Write /etc/docker/daemon.json from the user-provided option (already resolved
# to a local path by the _content_or_uri machinery), if any.
# ---------------------------------------------------------------------------
_docker_write_daemon_json() {
  [[ -n "${DAEMON_JSON:-}" && -f "${DAEMON_JSON}" ]] || {
    logging__skip "No daemon.json provided; using Docker defaults."
    return 0
  }
  logging__install "Writing /etc/docker/daemon.json."
  file__mkdir /etc/docker
  file__tee /etc/docker/daemon.json < "${DAEMON_JSON}" > /dev/null
  file__chmod 0644 /etc/docker/daemon.json
}

# ---------------------------------------------------------------------------
# DinD: seed /etc/containerd/config.toml disabling the erofs snapshotter.
# Some distros expose the erofs filesystem while shipping mkfs.erofs too old for
# containerd >= 2.3, which otherwise fails image pulls; force overlayfs.
# ---------------------------------------------------------------------------
_docker_write_containerd_config() {
  [[ -f /etc/containerd/config.toml ]] && {
    logging__skip "/etc/containerd/config.toml exists; leaving as-is."
    return 0
  }
  logging__install "Writing /etc/containerd/config.toml (erofs snapshotter disabled)."
  file__mkdir /etc/containerd
  printf 'version = 2\ndisabled_plugins = ["io.containerd.snapshotter.v1.erofs"]\n' |
    file__tee /etc/containerd/config.toml > /dev/null
}

# ---------------------------------------------------------------------------
# DinD: pin the iptables backend at install time (unless deferred to runtime).
# ---------------------------------------------------------------------------
_docker_select_iptables() {
  local _backend="${IPTABLES:-auto}"
  [[ "${IPTABLES_SWITCH_AT_RUNTIME:-false}" == "true" ]] && {
    logging__skip "iptables backend selection deferred to container runtime."
    return 0
  }
  [[ "${_backend}" == "auto" ]] && {
    logging__skip "iptables backend left at distro default (iptables=auto)."
    return 0
  }
  command -v update-alternatives > /dev/null 2>&1 || {
    logging__skip "update-alternatives unavailable; cannot set iptables backend."
    return 0
  }
  local _ipt _ip6t
  _ipt="/usr/sbin/iptables-${_backend}"
  _ip6t="/usr/sbin/ip6tables-${_backend}"
  logging__install "Setting iptables backend to '${_backend}'."
  users__run_privileged update-alternatives --set iptables "${_ipt}" 2> /dev/null || true
  users__run_privileged update-alternatives --set ip6tables "${_ip6t}" 2> /dev/null || true
}

# ---------------------------------------------------------------------------
# Binary method + host: install systemd unit files so enable_service works.
# Package methods ship their own units; the static tarball does not.
# ---------------------------------------------------------------------------
_docker_write_systemd_units() {
  _docker_systemd_active || {
    logging__skip "systemd not active; skipping unit generation for binary method."
    return 0
  }
  local _bin="/usr/local/bin"
  logging__install "Installing systemd units for the static-binary Docker install."
  file__mkdir /etc/systemd/system

  printf '%s\n' \
    '[Unit]' \
    'Description=containerd container runtime' \
    'Documentation=https://containerd.io' \
    'After=network.target local-fs.target' \
    '' \
    '[Service]' \
    'ExecStartPre=-/sbin/modprobe overlay' \
    "ExecStart=${_bin}/containerd" \
    'Type=notify' \
    'Delegate=yes' \
    'KillMode=process' \
    'Restart=always' \
    'RestartSec=5' \
    'LimitNPROC=infinity' \
    'LimitCORE=infinity' \
    'LimitNOFILE=infinity' \
    'TasksMax=infinity' \
    'OOMScoreAdjust=-999' \
    '' \
    '[Install]' \
    'WantedBy=multi-user.target' |
    file__tee /etc/systemd/system/containerd.service > /dev/null

  printf '%s\n' \
    '[Unit]' \
    'Description=Docker Socket for the API' \
    '' \
    '[Socket]' \
    'ListenStream=/run/docker.sock' \
    'SocketMode=0660' \
    'SocketUser=root' \
    'SocketGroup=docker' \
    '' \
    '[Install]' \
    'WantedBy=sockets.target' |
    file__tee /etc/systemd/system/docker.socket > /dev/null

  # $MAINPID is a systemd unit-file variable, not a shell expansion.
  # shellcheck disable=SC2016
  printf '%s\n' \
    '[Unit]' \
    'Description=Docker Application Container Engine' \
    'Documentation=https://docs.docker.com' \
    'After=network-online.target docker.socket firewalld.service containerd.service' \
    'Wants=network-online.target' \
    'Requires=docker.socket containerd.service' \
    '' \
    '[Service]' \
    'Type=notify' \
    "ExecStart=${_bin}/dockerd -H fd:// --containerd=/run/containerd/containerd.sock" \
    'ExecReload=/bin/kill -s HUP $MAINPID' \
    'TimeoutStartSec=0' \
    'RestartSec=2' \
    'Restart=always' \
    'LimitNOFILE=infinity' \
    'LimitNPROC=infinity' \
    'LimitCORE=infinity' \
    'TasksMax=infinity' \
    'Delegate=yes' \
    'KillMode=process' \
    'OOMScoreAdjust=-500' \
    '' \
    '[Install]' \
    'WantedBy=multi-user.target' |
    file__tee /etc/systemd/system/docker.service > /dev/null

  users__run_privileged systemctl daemon-reload 2> /dev/null || true
}

# ---------------------------------------------------------------------------
# Host: enable + start the docker service when systemd is the active init.
# ---------------------------------------------------------------------------
_docker_enable_service() {
  [[ "${ENABLE_SERVICE:-true}" == "true" ]] || {
    logging__skip "enable_service=false; not touching the docker service."
    return 0
  }
  _docker_systemd_active || {
    logging__skip "systemd not the active init; not enabling the docker service."
    return 0
  }
  logging__install "Enabling and starting the docker service."
  users__run_privileged systemctl enable --now docker 2> /dev/null ||
    logging__warn "Could not enable/start the docker service; start it manually with 'systemctl enable --now docker'."
}

# ---------------------------------------------------------------------------
# CLI plugins.
#  - Compose Switch: always (when opted in), from GitHub; docker-compose → v2.
#  - Buildx / Compose for the binary method: fetched from GitHub into the
#    cli-plugins dir. Package methods get these via option-gated packages.
# All plugin fetches are best-effort: a failure warns rather than aborting.
# ---------------------------------------------------------------------------
_docker_install_cli_plugins() {
  case "${METHOD:-}" in
    upstream-package | package) _docker_install_plugin_pkgs ;;
    binary) _docker_install_plugin_bins ;;
  esac
  if [[ "${INSTALL_COMPOSE_SWITCH:-true}" == "true" ]]; then
    _docker_install_compose_switch
  fi
}

# Package-based plugin install. Runs in finish_post, after the method install has
# added (and, with keep_repos, retained) the Docker repo — unlike the framework's
# option-gated deps, which run before the method adds the repo.
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

# Map (plugin, package manager) → the plugin's package name.
_docker_plugin_pkg() {
  local _plugin="$1" _pm="$2"
  case "${_pm}" in
    apt | dnf | yum) printf 'docker-%s-plugin' "${_plugin}" ;;
    apk) printf 'docker-cli-%s' "${_plugin}" ;;
    *) printf 'docker-%s' "${_plugin}" ;;
  esac
}

# Binary-method plugin install: fetch plugin binaries from GitHub into the
# cli-plugins directory. Best-effort.
_docker_install_plugin_bins() {
  file__mkdir /usr/libexec/docker/cli-plugins
  [[ "${INSTALL_BUILDX:-true}" == "true" ]] &&
    _docker_gh_plugin docker/buildx docker-buildx "buildx-{tag}.linux-$(os__release_arch --flavor go)"
  [[ "${INSTALL_COMPOSE:-true}" == "true" ]] &&
    _docker_gh_plugin docker/compose docker-compose "docker-compose-linux-$(os__arch)"
}

# _docker_gh_plugin <owner/repo> <plugin-name> <asset-template>
# <asset-template> may contain the literal {tag} token (replaced with the
# resolved release tag). Installs the asset as ${plugin_dir}/<plugin-name>.
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

# Compose Switch: legacy `docker-compose` → Compose v2 shim.
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
  # Route the legacy hyphenated command through the shim.
  file__ln -sf /usr/local/bin/compose-switch /usr/local/bin/docker-compose
}
