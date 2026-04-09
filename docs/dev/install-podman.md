# Rootless Podman — Development Notes

This document records the design decisions made,
problems encountered, and lessons learned
while building the feature.

---

## Motivation

The immediate use case that motivated this feature: running a command-line
tool distributed as an OCI image (e.g. a LaTeX/PDF processor) against a
workspace directory inside a devcontainer,
without needing Docker installed on the host or a daemon socket mounted into the container.

```sh
podman run --rm -v "$(pwd):/work" -w /work some-image some-tool --input file.md --output file.pdf
```

---

## Design decisions

### `privileged: true` over targeted capabilities

The first question was whether to use `privileged: true` or a chosen set of
`capAdd` / `securityOpt` overrides (e.g. `CAP_SYS_ADMIN`,
`seccomp=unconfined`, `apparmor=unconfined`).

Rootless Podman inside a container needs to:

- Create user namespaces (`clone(CLONE_NEWUSER)`) — blocked by the default
  seccomp profile
- Run setuid `newuidmap`/`newgidmap` — blocked by `nosuid` on the container
  root mount
- Mount `procfs` in child namespaces — blocked by Docker's `/proc` masks
- Access `/dev/net/tun` for networking

The combination of requirements adds up to near-privileged access anyway.
Using targeted overrides offers no meaningful security improvement in practice
(since anyone running rootless Podman inside a devcontainer already trusts that
container), while adding maintenance surface and fragility across container
runtimes. The official `docker-in-docker` feature uses the same `privileged:
true` approach for the same reasons.

### Named volume for storage

The first working approach used the container's writable layer
for Podman's image store.
This hit the **overlay-on-overlay** problem:
the Linux kernel rejects `exec` calls on filesystems
that are themselves overlayfs-backed,
which is exactly what the container's writable layer is.
The exec failure produces an opaque `Invalid argument` error
with no indication of the root cause.

The solution is to give Podman a named Docker volume mounted at a fixed path.
A named volume is backed by the host's actual filesystem (ext4, xfs, btrfs, etc.),
not overlayfs, so the native kernel overlay driver works correctly on top of it.
`fuse-overlayfs` was also considered as an alternative
but does not work in this environment (see [below](#fuse-overlayfs-does-not-work-in-this-environment)).

The volume name includes `${devcontainerId}`
so each devcontainer gets its own isolated image store.

### `graphRoot` in per-user `storage.conf`, not system config

Rootless Podman ignores the system-level `/etc/containers/storage.conf`
for `graphRoot` — it only reads the per-user `~/.config/containers/storage.conf`.
Only the per-user file is therefore written, inside the loop over resolved users.
Root is treated identically: if `add_root_user_config` is set, root gets
`/root/.config/containers/storage.conf`.

### The entrypoint: `mount --make-rshared /`

After the named volume fix, bind mounts like `-v $(pwd):/data` started
producing a warning: `"/" is not a shared mount`.
This is because Docker sets the container's root mount point to `private` propagation.
Rootless Podman creates a user namespace and tries to bind-mount host paths into it,
which requires the root mount to have `shared` (or `rshared`) propagation
so kernel mount events propagate across the namespace boundary.

The fix is a one-line entrypoint that runs at container startup
(before any Podman command): `mount --make-rshared /`.
This cannot be done at image build time because it requires a running container
— it is a runtime mount namespace operation.

The entrypoint script is generated during `install.sh` via `printf`
and installed at `/usr/local/share/install-podman/entrypoint`
(not in `$PATH`, since it is not a user-facing tool).
The `devcontainer-feature.json`'s `entrypoint` field points to it.

### `containers.conf`: cgroupfs and file event logger

When testing with `add_root_user_config: true`, Podman failed with:

```
WARN[0000] Failed to add conmon to cgroupfs sandbox cgroup: creating cgroup path
/libpod_parent/conmon: write /sys/fs/cgroup/cgroup.subtree_control: device or resource busy
Error: OCI runtime error: crun: the requested cgroup controller `pids` is not available
```

Root Podman defaults to the `systemd` cgroup manager and `journald` event logger.
Neither is available inside a Docker container (no systemd daemon is running).
Rootless Podman already defaults to `cgroupfs` and `file`, so only root was affected.

The fix is a system-level `/etc/containers/containers.conf` with:

```toml
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
```

This is written unconditionally (not only when root config is requested),
since it is harmless for rootless users and ensures correct behaviour whenever
root runs Podman in this container.

### Removing `userns = "keep-id"`

An early version of the feature set `userns = "keep-id"` in `containers.conf`.
This maps the host user's UID to the same UID inside every container, which
is useful for bind-mount permission consistency when the host user is
non-root.

It was removed because:

1. It is too opinionated as a global default. Most container images expect to
   run as root inside the container (i.e. UID 0). With `keep-id`, those images
   run as the host UID instead, which can break image-internal file permissions
   and package managers.
2. It is trivially opt-in per invocation: `podman run --userns=keep-id ...`.
3. The standard rootless Podman behaviour (host UID maps to container root) is
   what users familiar with Docker or Podman will expect.

### Networking: both `passt` and `slirp4netns`

The Podman 5.x release notes and Fedora packaging mark `slirp4netns` as
deprecated in favour of `passt`. The `passt` package was added to
`packages.txt` accordingly. However, the Debian/Ubuntu `podman` package still
configures `slirp4netns` as the default rootless network backend — removing
it caused a runtime error:

```
Error: could not find slirp4netns, the network namespace can't be configured:
exec: "slirp4netns": executable file not found in $PATH
```

Both packages are now installed. The active backend is whatever the distro's
`containers.conf` default selects.

### Package names for UID mapping tools

The package providing `newuidmap` and `newgidmap` has different names across
distributions:

| Distro family | Package name |
|---|---|
| Debian/Ubuntu (apt) | `uidmap` |
| Fedora/RHEL (dnf) | `shadow-utils` |
| Alpine (apk) | `shadow-uidmap` |

The `install-os-pkg` manifest selector syntax (`[pm=apt]`, `[pm=dnf]`,
`[pm=apk]`) handles this without shell conditionals in `install.sh`.

### Multi-user configuration model

The feature can configure Podman for multiple users (subuid/subgid + per-user
`storage.conf`). User sources:

| Option | Resolved to |
|---|---|
| `add_root_user_config` | literal `root` |
| `add_current_user_config` | `$SUDO_USER` if set and non-root, else `$(whoami)`, skipped if root |
| `add_remote_user_config` | `$_REMOTE_USER` if set (devcontainer tooling) |
| `add_container_user_config` | `$_CONTAINER_USER` if set (devcontainer tooling) |
| `add_user_config` | comma-separated explicit list |

Deduplication uses POSIX sh's `case` pattern matching against a
space-separated accumulator string — no `sort`, `uniq`, or arrays required.

`add_current_user_config` deliberately does not fall back to `_REMOTE_USER`.
Its purpose is standalone `sudo ./install.sh` invocations where `SUDO_USER`
identifies the invoking non-root user. In a devcontainer context (where the
script runs as root with no `SUDO_USER`), it is a no-op — `_REMOTE_USER` is
handled separately by `add_remote_user_config`.

### Subuid/subgid range allocation

Each user gets 65,536 UIDs/GIDs starting at an incrementing offset
(`SUBUID_OFFSET=100000`, `+65536` per user). The feature checks for an
existing entry before writing, so rebuilds are idempotent. The `graphRoot`
is `chmod 1777` (sticky + world-writable) so all configured users can access
the same named volume.

---

## Problems that no longer apply

### `fuse-overlayfs` does not work in this environment

Early iterations attempted to use `fuse-overlayfs` as the storage driver to
avoid the overlay-on-overlay problem. It failed: `fuse-overlayfs` requires
`/dev/fuse` and exhibits `noexec` behaviour in deeply nested user namespaces,
causing container exec calls to fail. It is **not installed** and **not used**.

The correct solution is the named volume: by mounting a Docker volume at
`/var/lib/containers/storage`, the storage path is backed by the host's real
filesystem, not overlayfs, so the native kernel overlay driver works without
any FUSE involvement.

### `configure-storage.sh` / `postStartCommand`

An early design used a `postStartCommand` script (`configure-storage.sh`)
that ran at container startup, detected whether `/dev/fuse` was accessible,
and wrote the appropriate `~/.config/containers/storage.conf`:

- If `/dev/fuse` was available: `driver = "overlay"` with `fuse-overlayfs` as the `mount_program`
- If not: `driver = "vfs"` — always works, but copies full layer contents for every container (slow, high disk usage)

This was the only host-agnostic way to handle storage at the time, since a
feature cannot request `--device=/dev/fuse` and `/dev/fuse` availability varies
by host. Once the named volume design was adopted — giving Podman storage backed
by the host's real filesystem rather than overlayfs — neither fuse-overlayfs nor
vfs was needed anymore. The native kernel overlay driver works on the named
volume unconditionally. All configuration is now done at image build time in
`install.sh`, and the runtime detection script is gone.

---

## References

- [Podman rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [Podman shortcomings of rootless](https://github.com/containers/podman/blob/main/rootless.md)
- [fuse-overlayfs](https://github.com/containers/fuse-overlayfs)
- [containers/storage.conf docs](https://github.com/containers/storage/blob/main/docs/containers-storage.conf.5.md)
- [devcontainers feature spec](https://containers.dev/implementors/features/)
