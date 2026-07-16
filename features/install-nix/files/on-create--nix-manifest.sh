#!/bin/sh
# Realize a deferred Nix manifest at container-create time.
#
# When the `manifest` option is a workspace-relative path that does not exist at
# image-build time, the build step defers realization to this onCreate hook,
# which runs once the workspace is mounted. MANIFEST is injected via the sidecar
# .conf (_conf_vars: [MANIFEST]); `warn` and the boilerplate come from the
# deployment wrapper.

[ -n "${MANIFEST:-}" ] || exit 0
if [ ! -e "${MANIFEST}" ]; then
  warn "manifest '${MANIFEST}' not found at container-create time; skipping."
  exit 0
fi

# Source whichever Nix profile is available — the multi-user system profile or
# the current user's single-user profile — then realize the manifest into the
# current (invoking) user's profile.
for _p in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
  "${HOME}/.nix-profile/etc/profile.d/nix.sh"; do
  # shellcheck disable=SC1090  # runtime-generated profile scripts
  [ -r "${_p}" ] && . "${_p}" && break
done

if ! command -v nix-env > /dev/null 2>&1; then
  warn "nix-env is not on PATH; cannot realize manifest '${MANIFEST}'."
  exit 0
fi

nix-env -if "${MANIFEST}" || warn "failed to realize Nix manifest '${MANIFEST}'."
