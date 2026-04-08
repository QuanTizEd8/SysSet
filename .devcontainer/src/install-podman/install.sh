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
    fuse-overlayfs \
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
# 4. Write system-wide Podman configuration (static — no runtime detection)
#
# containers.conf: keep-id maps the container user's UID into nested
# containers unchanged, preventing volume permission mismatches.
#
# storage.conf: driver and graphRoot are written at runtime by the
# entrypoint, because the optimal driver depends on host kernel version.
# ---------------------------------------------------------------------------
mkdir -p /etc/containers
printf '[containers]\nuserns = "keep-id"\n' > /etc/containers/containers.conf

# Pre-create the graphRoot directory for the named volume mount.
mkdir -p /var/lib/containers/storage
chown "${_REMOTE_USER}:${_REMOTE_USER}" /var/lib/containers/storage

# Save the remote user's home so the entrypoint can locate their config dir.
echo "${_REMOTE_USER_HOME}" > /usr/local/lib/podman-remote-user-home

# ---------------------------------------------------------------------------
# 5. Install entrypoint and helper scripts
# ---------------------------------------------------------------------------
cp "$(dirname "$0")/configure-storage.sh" /usr/local/bin/podman-configure-storage
chmod +x /usr/local/bin/podman-configure-storage

cp "$(dirname "$0")/podman-run-persistent" /usr/local/bin/podman-run-persistent
chmod +x /usr/local/bin/podman-run-persistent
