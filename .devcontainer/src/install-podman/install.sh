#!/bin/sh
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
#   VERSION, ADD_ROOT_USER_CONFIG, ADD_CURRENT_USER_CONFIG,
#   ADD_CONTAINER_USER_CONFIG, ADD_REMOTE_USER_CONFIG, ADD_USER_CONFIG
set -e

# ---------------------------------------------------------------------------
# Helper: add a username to _RESOLVED_USERS if not already present.
# ---------------------------------------------------------------------------
_RESOLVED_USERS=""

add_user() {
    _name="$1"
    [ -z "$_name" ] && return
    case " ${_RESOLVED_USERS} " in
        *" ${_name} "*) return ;;  # already in list
    esac
    _RESOLVED_USERS="${_RESOLVED_USERS} ${_name}"
}

# ---------------------------------------------------------------------------
# 1. Install packages
# ---------------------------------------------------------------------------
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    podman \
    uidmap \
    slirp4netns
rm -rf /var/lib/apt/lists/*

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
if [ "${ADD_ROOT_USER_CONFIG:-false}" = "true" ]; then
    add_user "root"
fi

if [ "${ADD_CURRENT_USER_CONFIG:-true}" = "true" ]; then
    _current="${SUDO_USER:-$(whoami)}"
    if [ -n "$_current" ] && [ "$_current" != "root" ]; then
        add_user "$_current"
    fi
fi

if [ "${ADD_REMOTE_USER_CONFIG:-true}" = "true" ]; then
    if [ -n "${_REMOTE_USER:-}" ]; then
        add_user "$_REMOTE_USER"
    fi
fi

if [ "${ADD_CONTAINER_USER_CONFIG:-true}" = "true" ]; then
    if [ -n "${_CONTAINER_USER:-}" ]; then
        add_user "$_CONTAINER_USER"
    fi
fi

if [ -n "${ADD_USER_CONFIG:-}" ]; then
    _saved_ifs="$IFS"
    IFS=','
    for _u in $ADD_USER_CONFIG; do
        IFS="$_saved_ifs"
        # trim spaces
        _u=$(echo "$_u" | tr -d ' ')
        [ -n "$_u" ] && add_user "$_u"
    done
    IFS="$_saved_ifs"
fi

if [ -z "$_RESOLVED_USERS" ]; then
    echo "install-podman: No users to configure." >&2
fi

# ---------------------------------------------------------------------------
# 4. Write Podman configuration
#
# containers.conf (system-level): keep-id maps the container user's UID
# into nested containers unchanged, preventing volume permission mismatches.
#
# storage.conf (per-user): native overlay on the named volume at
# /var/lib/containers/storage.  Avoids both the overlay-on-overlay problem
# and fuse-overlayfs's nested-userns noexec issue.  Written to each user's
# config dir because rootless Podman ignores the system-level graphRoot.
# ---------------------------------------------------------------------------
mkdir -p /etc/containers
printf '[containers]\nuserns = "keep-id"\n' > /etc/containers/containers.conf

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
