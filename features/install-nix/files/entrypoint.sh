#!/bin/sh
# Nix daemon startup for multi-user installs.
#
# Deployed as the feature's entrypoint and run at container start by the
# devcontainer CLI (which chains feature entrypoints and execs the container
# command — this script does its work and returns, it must NOT exec "$@").
#
# On a real host the Nix daemon is managed by systemd, but a container built by
# the devcontainer CLI has no init system, so nothing starts nix-daemon. This
# script launches it in the background. It is a no-op for single-user installs
# (NIX_MULTI_USER is injected via the sidecar .conf from _conf_vars: [NIX_MULTI_USER]).
#
# `warn` and the leading boilerplate (shebang, set -e, .conf sourcing, _SKIP
# handling) are provided by the deployment wrapper; see __deploy_lifecycle_scripts__.

# Single-user installs have no daemon.
[ "${NIX_MULTI_USER:-}" = "true" ] || exit 0

# Already running (e.g. restarted container, or a systemd host) — nothing to do.
if pidof nix-daemon > /dev/null 2>&1; then
  exit 0
fi

_nix_daemon="/nix/var/nix/profiles/default/bin/nix-daemon"
_nix_profile="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"

if [ ! -x "${_nix_daemon}" ]; then
  warn "nix-daemon not found at ${_nix_daemon}; multi-user Nix will be unavailable"
  exit 0
fi

# Start the daemon detached, as root directly or via passwordless sudo. Failures
# here must not abort container startup, so everything is best-effort.
if [ "$(id -u)" = "0" ]; then
  # shellcheck disable=SC1090  # runtime-generated profile script; absent at lint time
  (
    [ -r "${_nix_profile}" ] && . "${_nix_profile}"
    "${_nix_daemon}" > /tmp/nix-daemon.log 2>&1
  ) &
elif command -v sudo > /dev/null 2>&1 && sudo -n true 2> /dev/null; then
  sudo -n sh -c "[ -r '${_nix_profile}' ] && . '${_nix_profile}'; '${_nix_daemon}' > /tmp/nix-daemon.log 2>&1" &
else
  warn "cannot start nix-daemon (not root and no passwordless sudo); start it manually or set multi_user=single"
fi

exit 0
