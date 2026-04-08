#!/bin/sh
# install.sh — runs as root at image build time.
#
# Installs Podman and dependencies for rootless operation, registers the
# remote user's subuid/subgid ranges, writes static Podman config, and
# installs the startup entrypoint.
#
# Environment variables provided by the dev container tooling:
#   _REMOTE_USER       — the user the dev container will be used with
#   _REMOTE_USER_HOME  — home directory of that user
set -e

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
# At runtime, the entrypoint remounts / with suid so the kernel honours it.
# ---------------------------------------------------------------------------
chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Register subuid / subgid ranges for the remote user
# ---------------------------------------------------------------------------
if ! grep -q "^${_REMOTE_USER}:" /etc/subuid 2>/dev/null; then
    echo "${_REMOTE_USER}:100000:65536" >> /etc/subuid
fi
if ! grep -q "^${_REMOTE_USER}:" /etc/subgid 2>/dev/null; then
    echo "${_REMOTE_USER}:100000:65536" >> /etc/subgid
fi

# ---------------------------------------------------------------------------
# 4. Write Podman configuration
#
# containers.conf: keep-id maps the container user's UID into nested
# containers unchanged, preventing volume permission mismatches.
#
# storage.conf: native overlay on the named volume at /var/lib/containers/storage.
# Avoids both the overlay-on-overlay problem and fuse-overlayfs's nested-userns noexec issue.
# No fallback driver is provided — if overlay doesn't work, Podman will report a clear error.
# Written to the user's config dir because rootless Podman ignores the system-level graphRoot.
# ---------------------------------------------------------------------------
mkdir -p /etc/containers
printf '[containers]\nuserns = "keep-id"\n' > /etc/containers/containers.conf

GRAPH_ROOT="/var/lib/containers/storage"

# Pre-create the graphRoot directory for the named volume mount.
mkdir -p "${GRAPH_ROOT}"
chown "${_REMOTE_USER}:${_REMOTE_USER}" "${GRAPH_ROOT}"

# Write user-level storage.conf
if [ -n "${_REMOTE_USER_HOME}" ]; then
    CONFIG_DIR="${_REMOTE_USER_HOME}/.config/containers"
else
    CONFIG_DIR="/etc/containers"
fi

mkdir -p "${CONFIG_DIR}"
cat > "${CONFIG_DIR}/storage.conf" <<EOF
[storage]
driver = "overlay"
graphRoot = "${GRAPH_ROOT}"
EOF

# Fix ownership of user config directories so Podman can write to them
# at runtime (cni, containers, etc.).
if [ -n "${_REMOTE_USER_HOME}" ]; then
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${_REMOTE_USER_HOME}/.config"
fi

# ---------------------------------------------------------------------------
# 5. Install entrypoint
# ---------------------------------------------------------------------------
cp "$(dirname "$0")/configure-storage.sh" /usr/local/bin/podman-configure-storage
chmod +x /usr/local/bin/podman-configure-storage
