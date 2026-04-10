#!/usr/bin/env bash
# install.sh — runs as root at image build time.
#
# Installs Podman and dependencies for rootless operation, resolves the
# set of users to configure, registers their subuid/subgid ranges, writes
# per-user Podman storage config, and installs the startup entrypoint.
#
# Environment variables provided by the dev container tooling:
#   _REMOTE_USER       — the user the dev container will be used with
#   _REMOTE_USER_HOME  — home directory of that user
#   _CONTAINER_USER    — the containerUser from devcontainer.json
#
# Feature options (injected as environment variables by the tooling):
#   ADD_CURRENT_USER_CONFIG, ADD_REMOTE_USER_CONFIG, ADD_CONTAINER_USER_CONFIG,
#   ADD_USER_CONFIG, DEBUG, LOGFILE
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Debug / logging
# ---------------------------------------------------------------------------
if [ "${DEBUG:-false}" = "true" ]; then
    set -x
fi

# shellcheck source=_lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging::setup
trap 'logging::cleanup' EXIT

# ---------------------------------------------------------------------------
# Helper: add a username to _RESOLVED_USERS if not already present.
# ---------------------------------------------------------------------------
_RESOLVED_USERS=""

add_user() {
    local _name="$1"
    [ -z "$_name" ] && return 0
    case " ${_RESOLVED_USERS} " in
        *" ${_name} "*) return 0 ;;  # already in list
    esac
    _RESOLVED_USERS="${_RESOLVED_USERS} ${_name}"
    return 0
}

# ---------------------------------------------------------------------------
# 1. Install packages
# ---------------------------------------------------------------------------
if ! command -v install-os-pkg > /dev/null 2>&1; then
    echo "install-podman: install-os-pkg not found — it is a required dependency." >&2
    exit 1
fi

install-os-pkg --manifest "${_BASE_DIR}/packages.txt"

# ---------------------------------------------------------------------------
# 2. Ensure newuidmap / newgidmap have setuid bit
#
# The uidmap package ships these as setuid-root on Debian/Ubuntu.  Verify
# the bit is set — it is essential for rootless user-namespace creation.
# At runtime, privileged mode ensures nosuid is not applied.
# ---------------------------------------------------------------------------
chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Resolve user list
# ---------------------------------------------------------------------------
if [ "${ADD_CURRENT_USER_CONFIG:-true}" = "true" ]; then
    _current="${SUDO_USER:-$(whoami)}"
    if [ -n "$_current" ] && [ "$_current" != "root" ]; then
        add_user "$_current"
    fi
fi

if [ "${ADD_REMOTE_USER_CONFIG:-true}" = "true" ]; then
    if [ -n "${_REMOTE_USER:-}" ] && [ "$_REMOTE_USER" != "root" ]; then
        add_user "$_REMOTE_USER"
    fi
fi

if [ "${ADD_CONTAINER_USER_CONFIG:-true}" = "true" ]; then
    if [ -n "${_CONTAINER_USER:-}" ] && [ "$_CONTAINER_USER" != "root" ]; then
        add_user "$_CONTAINER_USER"
    fi
fi

if [ -n "${ADD_USER_CONFIG:-}" ]; then
    IFS=',' read -ra _extra_users <<< "$ADD_USER_CONFIG"
    for _u in "${_extra_users[@]}"; do
        _u="${_u// /}"  # trim spaces
        [ -n "$_u" ] && add_user "$_u"
    done
fi

if [ -z "$_RESOLVED_USERS" ]; then
    echo "install-podman: No users to configure." >&2
fi

# ---------------------------------------------------------------------------
# 4. Write Podman configuration
#
# storage.conf (per-user): native overlay on the named volume at
# /var/lib/containers/storage.  Avoids both the overlay-on-overlay problem
# and fuse-overlayfs's nested-userns noexec issue.  Written to each user's
# config dir because rootless Podman ignores the system-level graphRoot.
# ---------------------------------------------------------------------------
# Write system-level containers.conf.
# These settings are only required when running Podman as root. Rootless
# Podman already defaults to cgroupfs and file, but root defaults to the
# systemd cgroup manager and journald — neither of which is available inside
# a Docker container.
# - cgroup_manager=cgroupfs: no systemd inside the container, so the default
#   systemd manager would fail with cgroup.subtree_control errors at runtime.
# - events_logger=file: journald is not available inside the container.
mkdir -p /etc/containers
printf '[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' \
    > /etc/containers/containers.conf

GRAPH_ROOT="/var/lib/containers/storage"
mkdir -p "${GRAPH_ROOT}"

SUBUID_OFFSET=100000
for _username in $_RESOLVED_USERS; do
    if ! id "$_username" > /dev/null 2>&1; then
        echo "install-podman: User '${_username}' does not exist — skipping." >&2
        continue
    fi

    # Register subuid/subgid ranges (non-overlapping)
    if ! grep -q "^${_username}:" /etc/subuid 2>/dev/null; then
        echo "${_username}:${SUBUID_OFFSET}:65536" >> /etc/subuid
    fi
    if ! grep -q "^${_username}:" /etc/subgid 2>/dev/null; then
        echo "${_username}:${SUBUID_OFFSET}:65536" >> /etc/subgid
    fi
    SUBUID_OFFSET=$((SUBUID_OFFSET + 65536))

    # Write per-user storage.conf
    _home=$(eval echo "~${_username}")
    _config_dir="${_home}/.config/containers"
    mkdir -p "${_config_dir}"
    cat > "${_config_dir}/storage.conf" <<EOF
[storage]
driver = "overlay"
graphRoot = "${GRAPH_ROOT}"
EOF

    # Fix ownership so Podman can write to config dirs at runtime
    chown -R "${_username}:$(id -gn "$_username")" "${_home}/.config"
done

# Ensure the graphRoot is accessible to all configured users.
# With privileged mode + user namespaces, broad permissions are safe.
chmod 1777 "${GRAPH_ROOT}"

# ---------------------------------------------------------------------------
# 5. Install entrypoint:
#    Mark "/" as rshared so bind-mount propagation
#    works inside rootless Podman's user namespace.
# ---------------------------------------------------------------------------
mkdir -p /usr/local/share/install-podman
printf '#!/bin/sh\nmount --make-rshared /\n' > /usr/local/share/install-podman/entrypoint
chmod +x /usr/local/share/install-podman/entrypoint
