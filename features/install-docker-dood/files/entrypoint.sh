#!/bin/sh
#
# Docker-outside-of-Docker container entrypoint.
#
# Exposes the bind-mounted host Docker socket (SOCKET_PATH) at the path the CLI
# expects (TARGET_SOCKET), granting non-root access by aligning the container
# `docker` group's GID to the socket's group where possible, or proxying with
# socat otherwise. Config (SOCKET_PATH, TARGET_SOCKET, ENABLE_NONROOT) and
# `warn()` come from the deployed lifecycle-script boilerplate.

SOCKET_PATH="${SOCKET_PATH:-/var/run/docker-host.sock}"
TARGET_SOCKET="${TARGET_SOCKET:-/var/run/docker.sock}"

link_socket() {
  [ "$SOCKET_PATH" = "$TARGET_SOCKET" ] && return 0
  ln -sf "$SOCKET_PATH" "$TARGET_SOCKET" 2> /dev/null ||
    warn "could not link $SOCKET_PATH -> $TARGET_SOCKET"
}

start_socat_proxy() {
  if ! command -v socat > /dev/null 2>&1; then
    warn "socat not available; falling back to a direct link (non-root access may fail)"
    link_socket
    return 0
  fi
  [ "$SOCKET_PATH" = "$TARGET_SOCKET" ] && return 0
  rm -f "$TARGET_SOCKET" 2> /dev/null || true
  # Re-expose the socket group-readable so members of the `docker` group connect.
  (socat "UNIX-LISTEN:${TARGET_SOCKET},fork,mode=660,group=docker,backlog=128" \
    "UNIX-CONNECT:${SOCKET_PATH}" > /tmp/docker-socat.log 2>&1) &
}

forward_socket() {
  if [ ! -S "$SOCKET_PATH" ]; then
    warn "host Docker socket '$SOCKET_PATH' not found; is it bind-mounted into the container?"
    return 0
  fi

  # Root-only: a plain link is enough.
  if [ "${ENABLE_NONROOT:-true}" != "true" ]; then
    link_socket
    return 0
  fi

  sock_gid=$(stat -c '%g' "$SOCKET_PATH" 2> /dev/null || echo "")

  # A non-root group owns the socket: align the container `docker` group GID to
  # it (when that GID is free) so group members can use the socket directly.
  if [ -n "$sock_gid" ] && [ "$sock_gid" != "0" ]; then
    if getent group docker > /dev/null 2>&1; then
      cur_gid=$(getent group docker | cut -d: -f3)
      if [ "$cur_gid" != "$sock_gid" ] && ! getent group "$sock_gid" > /dev/null 2>&1; then
        groupmod -g "$sock_gid" docker 2> /dev/null ||
          warn "could not set 'docker' group GID to $sock_gid"
      fi
    fi
    link_socket
    return 0
  fi

  # Root-owned (or ungettable) socket: proxy so the docker group can connect.
  start_socat_proxy
}

forward_socket

if [ "$#" -eq 0 ]; then
  set -- sleep infinity
fi
exec "$@"
