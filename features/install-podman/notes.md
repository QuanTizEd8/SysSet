# Notes

## How it works

This feature runs rootless Podman inside a dev container. Most of its complexity
exists to make that work reliably across container runtimes; the sections below
explain what it configures and why.

### Packages installed

| Package | Package manager | Purpose |
|---|---|---|
| `podman` | all | The container engine. |
| `ca-certificates` | all | TLS certificates for pulling images from registries. |
| `passt` | all | Rootless networking backend; the default on Podman 5+ (Fedora, etc.). |
| `slirp4netns` | all | Rootless networking backend; still the default on Debian/Ubuntu. |
| `nftables` | all | `netavark` (the rootful network backend) calls `nft` to manage container network rules. |
| `uidmap` | `apt` | Provides the setuid `newuidmap`/`newgidmap` binaries (Debian/Ubuntu). |
| `shadow-utils` | `dnf`, `yum` | Provides `newuidmap`/`newgidmap` (Fedora/RHEL). |
| `shadow-uidmap` | `apk` | Provides `newuidmap`/`newgidmap` (Alpine). |
| `shadow` | `zypper`, `pacman` | Provides `newuidmap`/`newgidmap` (openSUSE, Arch). |

The package providing `newuidmap`/`newgidmap` is named differently on each
distribution, so it is selected per package manager. These setuid binaries are
required for rootless user-namespace creation; the feature verifies the setuid
bit is present at install time.

### Privileged mode

The feature sets `privileged: true` on the dev container automatically. Rootless
Podman inside a container needs to:

- create user namespaces (`clone(CLONE_NEWUSER)`) — blocked by the default seccomp profile in unprivileged containers;
- run setuid `newuidmap`/`newgidmap` — blocked by the `nosuid` flag on the container root mount;
- mount `procfs` in child namespaces — blocked by Docker's `/proc` masks;
- access `/dev/net/tun` for rootless networking.

These requirements collectively amount to near-privileged access, so targeted
`capAdd`/`securityOpt` overrides offer no meaningful security benefit over
`privileged: true`. This is the same approach the official `docker-in-docker`
feature uses.

### Named volume for storage

The feature mounts a named volume
(`podman-storage-devcontainer-${devcontainerId}`) at
`/var/lib/containers/storage`. The volume is backed by the host's real
filesystem (ext4, xfs, btrfs, …), not the container's overlayfs root. This lets
Podman use the native kernel overlay driver and avoids the **overlay-on-overlay**
problem: the kernel rejects `exec` on files that live on an overlayfs mount,
which is exactly what the container's writable layer is. The `${devcontainerId}`
in the volume name gives each dev container its own isolated image store.

### subuid / subgid ranges

Each configured user gets a non-overlapping 65,536-entry range registered in
`/etc/subuid` and `/etc/subgid`. These tell the kernel which host UIDs/GIDs the
user may map inside a user namespace; without them `podman run` fails
immediately with a user-namespace error. Existing entries are left untouched, so
rebuilds are idempotent.

### Per-user `storage.conf`

Rootless Podman ignores the system-level `/etc/containers/storage.conf` for
`graphRoot` and reads only the per-user `~/.config/containers/storage.conf`. In a
dev container build the feature therefore writes a per-user `storage.conf` for
each configured user, pointing `graphRoot` at that user's own subdirectory of the
named volume (`/var/lib/containers/storage/users/<username>`). Per-user
subdirectories prevent ownership conflicts: with a shared `graphRoot`, root
Podman would create `libpod/` as `root:root 0700` and lock other users out on
the next start. (On a standalone/host install this file is not written — the
default `~/.local/share/containers/storage` is correct there.)

### System-level `containers.conf`

In a dev container build the feature writes `/etc/containers/containers.conf` with
`cgroup_manager = "cgroupfs"` and `events_logger = "file"`. Rootless Podman
already defaults to these, but **root** Podman defaults to the `systemd` cgroup
manager and the `journald` logger — neither of which is available inside a Docker
container. (On a standalone/host install this file is left at Podman's defaults,
since systemd is present there.)

### Startup entrypoint

Some operations can only be performed in a running, privileged container, so the
feature ships an entrypoint script (deployed to
`/usr/local/share/quantized8/devfeats/install-podman/lifecycle-hooks/entrypoint.sh`
and referenced by the feature's `entrypoint` field). At container start it:

1. **Marks `/` as `rshared`** (`mount --make-rshared /`). Docker sets the
   container root mount to `private` propagation, which blocks bind-mount
   propagation into rootless Podman's user namespace and produces the
   `"/" is not a shared mount` warning.
2. **Enables cgroup v2 controller delegation.** Docker places container processes
   in the cgroup root; the kernel's "no internal process" rule then blocks writing
   `cgroup.subtree_control` (EBUSY), so root Podman cannot enable the
   `pids`/`memory`/… controllers for its `libpod_parent` hierarchy. The script
   moves all processes into `/sys/fs/cgroup/init/` and enables every available
   controller, mirroring the Moby
   [docker-in-docker](https://github.com/moby/moby/blob/master/hack/dind)
   approach. It is a no-op on cgroup v1.
3. **Ensures the shared graphRoot parent** (`/var/lib/containers/storage/users/`)
   exists with sticky, world-writable (`1777`) permissions on the named volume, so
   each configured user can create their own `graphRoot` subdirectory on first
   run. The named volume shadows the image layer at startup, so this must be
   re-applied at runtime.

All three operations are best-effort: each emits a `WARN` and continues if it
cannot be performed (see [Troubleshooting](#troubleshooting)).

### Default user-namespace mapping

The feature does **not** set `userns = "keep-id"`. Rootless containers therefore
map the host user to root (UID 0) inside the container — the standard
Docker/Podman default that most images expect. Pass `--userns=keep-id` per
invocation when you need the host UID preserved inside the container (e.g. for
bind-mount permission consistency):

```sh
podman run --rm -v "$(pwd):/work" --userns=keep-id -w /work some-image some-tool
```

### `containerUser` must be root

The entrypoint's `mount --make-rshared` and cgroup setup require `CAP_SYS_ADMIN`.
The devcontainer CLI runs feature entrypoints as `containerUser`, so if
`containerUser` is a non-root user both operations fail with permission denied.
Leave `containerUser` at its default (root); use `remoteUser` to control which
user the editor server and lifecycle commands run as, without changing the
container's OS user.

## Troubleshooting

### `cannot clone: Invalid argument` or `operation not permitted`

User namespaces are being blocked. Ensure `"privileged": true` is set (this
feature sets it automatically). On hardened Debian/Ubuntu hosts the host sysctl
`kernel.unprivileged_userns_clone` may also need to be `1`.

### `WARN: failed to set '/' mount propagation to rshared` (macOS only)

Expected on macOS Docker Desktop: its VM does not allow `mount --make-rshared /`
from inside containers even with `privileged: true`, and Podman's
`"/" is not a shared mount` warning will persist. Basic container usage
(`podman run`, `podman pull`) is unaffected.

### `WARN: could not create /sys/fs/cgroup/init` (macOS or non-root)

On macOS Docker Desktop, cgroupfs writes are blocked at the VM level even for root
containers; when `containerUser` is non-root, `CAP_SYS_ADMIN` is absent. In both
cases Podman falls back to cgroupfs management without full controller delegation,
and `podman run` still works for typical usage.

### `OCI runtime error: the requested cgroup controller 'pids' is not available`

Occurs when running Podman as **root** on a cgroup v2 host before the entrypoint
has performed cgroup delegation. If the entrypoint has not run (e.g. the container
was started outside a devcontainer lifecycle), run it manually:

```sh
/usr/local/share/quantized8/devfeats/install-podman/lifecycle-hooks/entrypoint.sh
```

### `newuidmap: write to uid_map failed: Operation not permitted`

Either `newuidmap` lacks the setuid bit, or the user has no `/etc/subuid` entry.
The feature sets both at install time. To inspect:

```sh
grep "$USER" /etc/subuid /etc/subgid
ls -la "$(command -v newuidmap)"   # should show -rwsr-xr-x
```

### `slirp4netns: failed to execute` / no network inside containers

Both `slirp4netns` and `passt` are installed. To force a specific backend, set it
in `~/.config/containers/containers.conf`:

```toml
[network]
default_rootless_network_cmd = "slirp4netns"
```

### `short-name "..." did not resolve to an alias`

Podman does not pull by short name without a configured search registry. Use
fully-qualified image names (e.g. `docker.io/library/hello-world`) or add
`docker.io` to `/etc/containers/registries.conf`:

```toml
unqualified-search-registries = ["docker.io"]
```

## References

- [Podman rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [Podman rootless shortcomings](https://github.com/containers/podman/blob/main/rootless.md)
- [Podman troubleshooting guide](https://github.com/containers/podman/blob/main/troubleshooting.md)
- [`containers-storage.conf` reference](https://github.com/containers/storage/blob/main/docs/containers-storage.conf.5.md)
- [Dev Container Features specification](https://containers.dev/implementors/features/)
