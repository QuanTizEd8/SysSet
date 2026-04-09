# Rootless Podman

Installs [Podman](https://podman.io/) for rootless container execution inside a
dev container. Uses native kernel overlay storage on a named volume for fast,
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
