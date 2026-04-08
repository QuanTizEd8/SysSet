# Rootless Podman in a Dev Container

## Purpose

This devcontainer exists to test and validate running rootless Podman inside a VS Code Dev Container. The primary use case is pulling an OCI image, mounting a workspace directory into it, running a command, and getting output files back — for example:

```sh
podman run --rm -v "$(pwd):/work" -w /work some-image some-tool --input ./file.md --output ./file.pdf
```

---

## Current Setup

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the container image from `ubuntu:latest` with Podman and all dependencies |
| `configure-storage.sh` | Entrypoint script that detects `/dev/fuse` availability at startup and writes the appropriate Podman storage config |
| `devcontainer.json` | Configures VS Code to use the Dockerfile; sets `privileged: true` and runs `configure-storage.sh` via `postStartCommand` |

### What's installed and why

**`podman`** — the container tool itself, installed from Ubuntu's apt repositories.

**`uidmap`** — provides the `newuidmap` and `newgidmap` setuid binaries. These are what actually perform the UID/GID remapping that makes rootless containers possible. Without them, `podman run` fails immediately with a user namespace error.

**`fuse-overlayfs`** — a FUSE-based userspace implementation of the overlay filesystem. The standard kernel `overlay` driver requires `CAP_SYS_ADMIN` at the filesystem level which is not available inside a container even with `--privileged`. `fuse-overlayfs` serves as a drop-in replacement and works in userspace.

**`slirp4netns`** — a userspace network stack for rootless containers. Podman 5.x defaults to `pasta` (from the `passt` package), but `slirp4netns` is more reliably available on Ubuntu LTS and works equivalently for simple use cases. If `pasta` is preferred, replace `slirp4netns` with `passt` in the Dockerfile.

### Runtime flags

**`privileged: true`** ([dedicated spec field](https://containers.dev/implementors/json_reference/)) — required so the devcontainer itself can create nested user namespaces. Rootless Podman works by creating a new user namespace (`clone(CLONE_NEWUSER)`) to remap UIDs. The Linux kernel blocks this syscall unless the host container is privileged. `privileged` is also a first-class field in `devcontainer-feature.json`, so it carries over cleanly when this is packaged as a feature.

### `/etc/subuid` and `/etc/subgid`

Rootless Podman requires the running user to have a subordinate UID/GID range registered in `/etc/subuid` and `/etc/subgid`. These files tell the kernel which UIDs/GIDs the user is allowed to "own" inside a user namespace. The Dockerfile adds:

```
devuser:100000:65536
```

This gives `devuser` a range of 65,536 UIDs starting at 100000. This is the standard range used by most Linux distributions when creating users with `useradd`.

### `configure-storage.sh` / `postStartCommand`

The `devcontainer-feature.json` spec has **no `runArgs` or `devices` field** — a feature cannot request `--device=/dev/fuse`. To be host-agnostic, storage configuration cannot be baked into the image at build time.

Instead, `configure-storage.sh` (installed at `/usr/local/bin/podman-configure-storage`) runs at container startup via `postStartCommand`. It detects whether `/dev/fuse` is accessible at runtime and writes the appropriate config to `~/.config/containers/`:

| Host provides `/dev/fuse` | Driver chosen | Notes |
|---|---|---|
| Yes | `overlay` + `fuse-overlayfs` | Fast, space-efficient |
| No | `vfs` | Always works, slower |

This script is the direct equivalent of the `entrypoint` field in `devcontainer-feature.json`, making the eventual feature conversion straightforward.

### `~/.config/containers/storage.conf`

Written by `configure-storage.sh` at startup. If `/dev/fuse` is available:

```toml
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
```

> **Important:** `mount_program` must be under `[storage.options.overlay]`, not `[storage.options]`. The wrong section is silently ignored and Podman falls back to the kernel overlay driver, which fails inside a nested container with an opaque `Invalid argument` error.

If `/dev/fuse` is not available:

```toml
[storage]
driver = "vfs"
```

### `~/.config/containers/containers.conf`

Also written by `configure-storage.sh`. Sets `keep-id` as the default user namespace mode:

```toml
[containers]
userns = "keep-id"
```

With `keep-id`, the devuser's UID on the host is mapped to the same UID inside any nested container, which is required for fuse-overlayfs to work correctly and prevents volume permission mismatches.

---

## Running containers as the devuser

The `remoteUser` in `devcontainer.json` is set to `devuser`. All Podman commands should be run as this user.

Example:

```sh
podman run --rm \
  -v "$(pwd):/work" \
  -w /work \
  some-image \
  some-tool --input ./file.md --output ./file.pdf
```

The `keep-id` user namespace mode is active by default (see `~/.config/containers/containers.conf`, written at startup), so your host UID matches the UID inside the nested container and files written to the mounted volume are owned by you.

---

## Known Failure Modes and Fixes

### 1. `ERRO[0000] cannot clone: Invalid argument`

**Cause:** User namespaces are being blocked by the kernel. The devcontainer is not running with `--privileged`, or the host kernel has `kernel.unprivileged_userns_clone = 0`.

**Fix:** Ensure `"privileged": true` is present in `devcontainer.json` (it is a dedicated first-class field in the spec, not a `runArgs` entry). If running on a host that restricts user namespaces (some hardened Debian/Ubuntu installs do), the host sysctl `kernel.unprivileged_userns_clone` must be set to `1`.

### 2. `fuse: device not found, try 'modprobe fuse' first`

**Cause:** `/dev/fuse` is not present inside the devcontainer, but `configure-storage.sh` somehow selected `fuse-overlayfs` anyway.

**This should not happen** with the current setup — `configure-storage.sh` checks `/dev/fuse` writeability before selecting fuse-overlayfs and falls back to `vfs` automatically. If you see this error, the startup script may not have run. Trigger it manually:

```sh
podman-configure-storage
```

Then verify the chosen driver:

```sh
cat ~/.config/containers/storage.conf
```

### 3. `exec container process …: Invalid argument` when running any image

**Cause:** Podman is using the kernel overlay driver on top of an overlayfs filesystem (overlay-on-overlay). The kernel rejects exec attempts from such mounts with `EINVAL`. This happens when `storage.conf` is misconfigured — in particular when `mount_program` is placed in the wrong TOML section (`[storage.options]` instead of `[storage.options.overlay]`), causing the option to be silently ignored.

**Fix:** Verify `~/.config/containers/storage.conf` inside the container (written by `podman-configure-storage` at startup) contains:

```toml
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
```

The section name `[storage.options.overlay]` is mandatory. If you also see the `"/" is not a shared mount` warning alongside this error, verify `~/.config/containers/containers.conf` sets `userns = "keep-id"`.

### 4. `newuidmap: write to uid_map failed: Operation not permitted`

**Cause:** The `newuidmap` binary is not setuid, or the `/etc/subuid` entry for the user is missing or malformed.

**Fix:**
```sh
# Check subuid entry exists
grep devuser /etc/subuid

# Check newuidmap is setuid root
ls -la $(which newuidmap)
# Should show: -rwsr-xr-x root root ...

# If not setuid:
sudo chmod u+s $(which newuidmap)
sudo chmod u+s $(which newgidmap)
```

### 5. `Error: cannot re-exec process` or immediate exit with no error

**Cause:** The `podman` binary cannot find `newuidmap`/`newgidmap` or they are not in `$PATH`.

**Fix:** Ensure `uidmap` is installed. On Ubuntu/Debian, `newuidmap` and `newgidmap` are installed to `/usr/bin/`. Verify:
```sh
which newuidmap newgidmap
```

### 6. Network not working inside containers (`slirp4netns: failed to execute`)

**Cause:** Neither `slirp4netns` nor `passt` is installed, or the wrong one is configured.

**Fix on Ubuntu:** `slirp4netns` is in the apt repos. `passt` (which provides the `pasta` command, Podman 5.x default) may not be. Check Podman version and configure accordingly in `/etc/containers/containers.conf`:

```toml
[network]
default_rootless_network_cmd = "slirp4netns"
```

If network is not needed at all for the use case (e.g., a LaTeX compiler image that only reads/writes files), add `--network=none` to the `podman run` command to skip network setup entirely.

### 7. `x509: certificate signed by unknown authority` when pulling images

**Cause:** The base image (e.g. `ubuntu:latest`) does not include CA certificates, so Podman cannot verify the TLS certificate of the container registry.

**Immediate fix** (no rebuild needed):
```sh
podman run --rm --tls-verify=false --userns=keep-id -v "$(pwd):/work" -w /work some-image some-tool
```

**Permanent fix:** Add `ca-certificates` to the `apt-get install` step in the Dockerfile. The Dockerfile in this folder already includes it.

### 8. Image store is root-owned / permission errors on first pull

**Cause:** Podman was invoked once as root (e.g., during a `RUN` in the Dockerfile), leaving root-owned files in the image store.

**Fix:** The image store for `devuser` should be at `~/.local/share/containers/storage`. If it was created by root, delete it and re-run as `devuser`:
```sh
sudo rm -rf /home/devuser/.local/share/containers
podman system reset
```

---

## Alternative: Using the `vfs` storage driver

`configure-storage.sh` automatically selects `vfs` when `/dev/fuse` is unavailable, so no manual intervention is needed. If you want to force `vfs` regardless of `/dev/fuse` availability, run:

```sh
printf '[storage]\ndriver = "vfs"\n' > ~/.config/containers/storage.conf
```

`vfs` copies full layer contents for every container. It is functionally correct but slower and uses more disk space.

---

## Alternative: Docker-in-Docker

If rootless Podman continues to be problematic, the existing `devcontainer.json` at the repo root already has the `ghcr.io/devcontainers/features/docker-in-docker:2` feature configured (which is the official Microsoft-maintained feature). Docker-in-Docker:

- Runs a full `dockerd` daemon inside the devcontainer
- Requires `--privileged` as well (same host requirement)
- Does **not** need `/dev/fuse` or `subuid`/`subgid`
- The Docker socket is at `/var/run/docker.sock` and the daemon starts via a `postStart` script
- The `docker run -v $(pwd):/work` syntax works identically

The command becomes:
```sh
docker run --rm -v "$(pwd):/work" -w /work some-image some-tool --input ./file.md --output ./file.pdf
```

---

## References

- [Podman rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [Shortcomings of rootless Podman](https://github.com/containers/podman/blob/main/rootless.md)
- [fuse-overlayfs](https://github.com/containers/fuse-overlayfs)
- [slirp4netns](https://github.com/rootless-containers/slirp4netns)
- [containers/storage.conf docs](https://github.com/containers/storage/blob/main/docs/containers-storage.conf.5.md)
- [devcontainers/features (official)](https://github.com/devcontainers/features/tree/main/src)
