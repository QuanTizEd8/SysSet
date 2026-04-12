# Rootless Podman

Installs [Podman](https://podman.io/)
for rootless container execution inside a dev container.
Uses native kernel overlay storage on a named volume for fast,
space-efficient copy-on-write image management.

---

## Usage

### Basic

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/install-podman:0": {}
  }
}
```

With the defaults above, Podman is configured for both `remoteUser` and
`containerUser` as set by the devcontainer tooling. Run containers as normal:

```sh
podman run --rm hello-world
podman run --rm -v "$(pwd):/work" --userns=keep-id -w /work some-image some-tool
```

### Also configure root

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-podman:0": {
      "add_user_config": "root"
    }
  }
}
```

### Configure a specific additional user

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-podman:0": {
      "add_user_config": "myuser"
    }
  }
}
```

---

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `add_current_user_config` | boolean | `true` | Configure Podman for the current non-root user (`SUDO_USER` if run via `sudo`, otherwise `whoami`). No effect when the current user is root. |
| `add_remote_user_config` | boolean | `true` | Configure Podman for `remoteUser` as set by the devcontainer tooling. No effect when running standalone. |
| `add_container_user_config` | boolean | `true` | Configure Podman for `containerUser` as set by the devcontainer tooling. No effect when running standalone. |
| `add_user_config` | string | `""` | Comma-separated list of additional usernames to configure. |

---

## How it works

### Packages installed

| Package | Distro(s) | Purpose |
|---|---|---|
| `podman` | all | The container engine |
| `ca-certificates` | all | TLS certificates for pulling images from registries |
| `passt` | all | Default rootless networking backend on Podman 5+ (Fedora, etc.) |
| `slirp4netns` | all | Rootless networking backend; still the default on Debian/Ubuntu |
| `uidmap` | apt | Provides `newuidmap`/`newgidmap` setuid binaries (Debian/Ubuntu) |
| `shadow-utils` | dnf | Provides `newuidmap`/`newgidmap` (Fedora/RHEL) |
| `shadow-uidmap` | apk | Provides `newuidmap`/`newgidmap` (Alpine) |

### `privileged: true`

Rootless Podman requires the devcontainer itself to run with `--privileged`. The feature sets this automatically. It is needed to:

- Create user namespaces (`clone(CLONE_NEWUSER)`) — blocked by default seccomp in unprivileged containers
- Run setuid `newuidmap`/`newgidmap` — blocked by the `nosuid` mount flag on the container root
- Mount `procfs` in child namespaces — blocked by Docker's `/proc` masks
- Access `/dev/net/tun` for rootless networking

This is the same approach used by the official `docker-in-docker` devcontainer feature.

### Named volume for storage

The feature mounts a named volume at `/var/lib/containers/storage`:

```jsonc
{
  "source": "podman-storage-devcontainer-${devcontainerId}",
  "target": "/var/lib/containers/storage",
  "type": "volume"
}
```

The volume is backed by the host's real filesystem (ext4, xfs, btrfs, etc.),
not the container's overlayfs root. This avoids the **overlay-on-overlay**
problem: the Linux kernel rejects `exec` calls from filesystems that are
themselves overlayfs-backed, which is what you would get if Podman stored
images in the container's writable layer.

### subuid / subgid ranges

Each configured user gets a non-overlapping 65,536-entry range registered in
`/etc/subuid` and `/etc/subgid`. These tell the kernel which host UIDs/GIDs
the user is allowed to map inside a user namespace. Without these entries
`podman run` fails immediately with a user namespace error.

### Per-user `storage.conf`

A `~/.config/containers/storage.conf` is written for each configured user,
pointing `graphRoot` at the shared named volume. This is necessary because
rootless Podman ignores the system-level storage default and reads only the
per-user config file.

### System-level `containers.conf`

A `/etc/containers/containers.conf` is written with:

```toml
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
```

These settings are primarily needed when running Podman as **root**. Rootless
Podman already defaults to `cgroupfs` and `file`, but root Podman defaults to
`systemd` and `journald` — neither of which is available inside a Docker
container.

### Entrypoint: `mount --make-rshared /`

The feature installs an entrypoint script at
`/usr/local/share/install-podman/entrypoint` that runs
`mount --make-rshared /` at container startup. Docker sets the container root
mount to `private` propagation by default, which blocks bind-mount propagation
into rootless Podman's user namespace and produces the warning
`"/" is not a shared mount`.

---

## Troubleshooting

### `cannot clone: Invalid argument` or `operation not permitted`

User namespaces are being blocked. Ensure `"privileged": true` is set in your
`devcontainer.json` (this feature sets it automatically). On hardened
Debian/Ubuntu hosts the host sysctl
`kernel.unprivileged_userns_clone` may also need to be `1`.

### `OCI runtime error: the requested cgroup controller 'pids' is not available`

Occurs when running Podman as **root**. Root Podman defaults to the `systemd`
cgroup manager, which requires a running systemd. Either use
`add_user_config: "root"` so the feature writes the corrective
`containers.conf`, or run as a non-root user.

### `newuidmap: write to uid_map failed: Operation not permitted`

Either `newuidmap` lacks the setuid bit, or the user has no `/etc/subuid`
entry. The feature sets both at install time. To inspect:

```sh
grep "$USER" /etc/subuid /etc/subgid
ls -la $(which newuidmap)   # should show -rwsr-xr-x
```

### `slirp4netns: failed to execute` / no network inside containers

Both `slirp4netns` and `passt` are installed. If Podman cannot find whichever
it expects, the active default can be overridden in
`~/.config/containers/containers.conf`:

```toml
[network]
default_rootless_network_cmd = "slirp4netns"
```

### `short-name "..." did not resolve to an alias`

Podman does not allow pulling by short name without a configured search registry.
Use fully-qualified image names:

```sh
podman run --rm docker.io/library/hello-world
```

Or add `docker.io` to `/etc/containers/registries.conf`:

```toml
unqualified-search-registries = ["docker.io"]
```




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
container), while adding maintenance surface and fragility across container runtimes.
The official [`docker-in-docker`](https://github.com/devcontainers/features/blob/3df3aed1e7bfcdd91e97fa2d5d7cbefff1dde4cf/src/docker-in-docker/devcontainer-feature.json#L66)
feature uses the same `privileged: true` approach for the same reasons.

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
`base.yaml` accordingly. However, the Debian/Ubuntu `podman` package still
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

The `install-os-pkg` manifest uses PM-specific blocks (`apt:`, `dnf:`,
`apk:`) to handle this without shell conditionals in `install.sh`.

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
- [Podman troubleshooting guide](https://github.com/containers/podman/blob/main/troubleshooting.md)
- [fuse-overlayfs](https://github.com/containers/fuse-overlayfs)
- [containers/storage.conf docs](https://github.com/containers/storage/blob/main/docs/containers-storage.conf.5.md)
- [devcontainers feature spec](https://containers.dev/implementors/features/)
