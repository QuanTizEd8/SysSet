#!/bin/sh
# install.sh — runs as root at image build time.
#
# Installs Podman and all dependencies for rootless operation, registers the
# remote user's subuid/subgid ranges, and installs the startup entrypoint that
# selects the appropriate storage driver at runtime.
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
# 2. Register subuid / subgid ranges for the remote user
#
# Rootless Podman requires the user to have a subordinate UID/GID range in
# /etc/subuid and /etc/subgid. useradd normally sets these up, but the remote
# user may already exist (pre-existing base image user) without an entry.
# We add the entry only if it is not already present.
# ---------------------------------------------------------------------------
if ! grep -q "^${_REMOTE_USER}:" /etc/subuid 2>/dev/null; then
    echo "${_REMOTE_USER}:100000:65536" >> /etc/subuid
fi
if ! grep -q "^${_REMOTE_USER}:" /etc/subgid 2>/dev/null; then
    echo "${_REMOTE_USER}:100000:65536" >> /etc/subgid
fi

# ---------------------------------------------------------------------------
# 3. Write system-wide Podman configuration
#
# containers.conf: keep-id maps the container user's UID into nested
# containers unchanged — required for fuse-overlayfs and prevents volume
# permission mismatches. This is static and the same for all users, so it
# belongs here at build time rather than in the runtime-detection script.
#
# storage.conf: driver selection depends on /dev/fuse availability at
# runtime (the feature spec has no 'runArgs'/'devices' field, so the host
# may or may not expose /dev/fuse). That is handled by configure-storage.sh
# via the feature entrypoint.
# ---------------------------------------------------------------------------
mkdir -p /etc/containers
printf '[containers]\nuserns = "keep-id"\n' > /etc/containers/containers.conf

# Pre-create the graphRoot directory that the named volume will be mounted at.
# The volume mount happens after image build, so the directory must exist in
# the image for the mount to work correctly. Ownership is set to the remote
# user so rootless Podman can write to it without privilege escalation.
mkdir -p /var/lib/containers/storage
chown "${_REMOTE_USER}:${_REMOTE_USER}" /var/lib/containers/storage

# Save the remote user's home directory so the entrypoint can find it at
# container startup time (where _REMOTE_USER_HOME is not available).
echo "${_REMOTE_USER_HOME}" > /usr/local/lib/podman-remote-user-home

# ---------------------------------------------------------------------------
# 4. Install the storage-configuration entrypoint
#
# This script is declared as "entrypoint" in devcontainer-feature.json and
# fires at every container startup. It cannot write config at build time
# because storage driver selection depends on whether /dev/fuse is exposed by
# the host runtime — something only known at startup, not at image build time.
# ---------------------------------------------------------------------------
cp "$(dirname "$0")/configure-storage.sh" /usr/local/bin/podman-configure-storage
chmod +x /usr/local/bin/podman-configure-storage

cp "$(dirname "$0")/podman-run-persistent" /usr/local/bin/podman-run-persistent
chmod +x /usr/local/bin/podman-run-persistent
