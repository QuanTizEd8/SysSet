# Rootless Podman in a Dev Container

## Purpose

This devcontainer exists to test and validate running rootless Podman inside a VS Code Dev Container. The primary use case is pulling an OCI image, mounting a workspace directory into it, running a command, and getting output files back — for example:

```sh
podman run --rm --userns=keep-id -v "$(pwd):/work" -w /work some-image some-tool --input ./file.md --output ./file.pdf
```

---

## Current Setup

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the container image from `ubuntu:latest` with Podman and all dependencies |
| `devcontainer.json` | Configures VS Code to use the Dockerfile, passes `--privileged` and `--device=/dev/fuse` to the host container runtime |

### What's installed and why

**`podman`** — the container tool itself, installed from Ubuntu's apt repositories.

**`uidmap`** — provides the `newuidmap` and `newgidmap` setuid binaries. These are what actually perform the UID/GID remapping that makes rootless containers possible. Without them, `podman run` fails immediately with a user namespace error.

**`fuse-overlayfs`** — a FUSE-based userspace implementation of the overlay filesystem. The standard kernel `overlay` driver requires `CAP_SYS_ADMIN` at the filesystem level which is not available inside a container even with `--privileged`. `fuse-overlayfs` serves as a drop-in replacement and works in userspace.

**`slirp4netns`** — a userspace network stack for rootless containers. Podman 5.x defaults to `pasta` (from the `passt` package), but `slirp4netns` is more reliably available on Ubuntu LTS and works equivalently for simple use cases. If `pasta` is preferred, replace `slirp4netns` with `passt` in the Dockerfile.

### Runtime flags

**`--privileged`** — required so the devcontainer itself can create nested user namespaces. Rootless Podman works by creating a new user namespace (`clone(CLONE_NEWUSER)`) to remap UIDs. The Linux kernel blocks this syscall unless the host container is privileged. Note: `--privileged` grants broad host access; this is a known trade-off with no cleaner alternative at present.

**`--device=/dev/fuse`** — exposes the host's FUSE device into the devcontainer so `fuse-overlayfs` can create FUSE mounts for image layers. Without this, `fuse-overlayfs` fails to mount and Podman cannot unpack or run any image.

### `/etc/subuid` and `/etc/subgid`

Rootless Podman requires the running user to have a subordinate UID/GID range registered in `/etc/subuid` and `/etc/subgid`. These files tell the kernel which UIDs/GIDs the user is allowed to "own" inside a user namespace. The Dockerfile adds:

```
devuser:100000:65536
```

This gives `devuser` a range of 65,536 UIDs starting at 100000. This is the standard range used by most Linux distributions when creating users with `useradd`.

### `/etc/containers/storage.conf`

By default, Podman tries to use the kernel overlay driver for its image store. Inside a container this fails silently or with a cryptic error. The Dockerfile writes a system-wide `storage.conf` that explicitly sets:

```toml
[storage]
driver = "overlay"

[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"
```

This tells Podman to use the overlay driver but delegate all mounts to `fuse-overlayfs` instead of the kernel.

---

## Running containers as the devuser

The `remoteUser` in `devcontainer.json` is set to `devuser`. All Podman commands should be run as this user. The key flag to use when mounting workspace directories is:

```sh
--userns=keep-id
```

Without this, the container runs with `root` inside the user namespace even though it is `devuser` on the host. Files written to the mounted volume would appear as owned by `devuser` on the host anyway (due to UID mapping), but `--userns=keep-id` makes the UID inside and outside the container match, which avoids permission issues when the image's process runs as a non-root user.

Full example:

```sh
podman run --rm \
  --userns=keep-id \
  -v "$(pwd):/work" \
  -w /work \
  some-image \
  some-tool --input ./file.md --output ./file.pdf
```

---

## Known Failure Modes and Fixes

### 1. `ERRO[0000] cannot clone: Invalid argument`

**Cause:** User namespaces are being blocked by the kernel. The devcontainer is not running with `--privileged`, or the host kernel has `kernel.unprivileged_userns_clone = 0`.

**Fix:** Ensure `"runArgs": ["--privileged"]` is present in `devcontainer.json`. If running on a host that restricts user namespaces (some hardened Debian/Ubuntu installs do), the host sysctl `kernel.unprivileged_userns_clone` must be set to `1`.

### 2. `fuse: device not found, try 'modprobe fuse' first`

**Cause:** `/dev/fuse` is not present inside the devcontainer.

**Fix:** Ensure `"--device=/dev/fuse"` is in `runArgs`. On some host Docker setups this device is not available at all (e.g., some CI environments), in which case `vfs` storage driver can be used as a last resort (very slow, no deduplication):

```toml
[storage]
driver = "vfs"
```

### 3. `Error: 'overlay' is not supported over overlayfs`

**Cause:** Podman is attempting to use the kernel overlay driver, but the devcontainer's filesystem is already an overlayfs (which is the case for most container runtimes). Kernel overlay-on-overlay is not supported.

**Fix:** The `storage.conf` with `mount_program = "/usr/bin/fuse-overlayfs"` should prevent this. If this error still appears, the `storage.conf` is not being read. Verify it exists at `/etc/containers/storage.conf` inside the container and contains the correct content. Also check that `~/.config/containers/storage.conf` doesn't exist with conflicting content (user config overrides system config).

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

If `fuse-overlayfs` cannot be made to work (e.g. `/dev/fuse` unavailable on the host), replace the `storage.conf` in the Dockerfile with:

```toml
[storage]
driver = "vfs"
```

`vfs` does not use any overlay mechanism — it copies the full layer contents for every container. This is functionally correct but uses significantly more disk space and is slower to start containers. It requires no special kernel support and works anywhere.

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
