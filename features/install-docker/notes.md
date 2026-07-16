# install-docker — design notes

Installs the Docker **engine + CLI** on a host or as **Docker-in-Docker** in a
devcontainer. The socket-forwarding **Docker-outside-of-Docker** case is a
separate feature, [`install-docker-dood`](../install-docker-dood/), for the
reason below.

## Why DinD and DooD are separate features

A `devcontainer-feature.json` bakes its static container config
(`privileged`, `mounts`, `init`, `securityOpt`, `entrypoint`, `containerEnv`)
into the image `devcontainer.metadata` label **before** any `install.sh` runs,
and those fields **cannot** vary by an option value: feature metadata supports
only `${devcontainerId}` substitution (in `entrypoint`/`mounts`/`customizations`),
never option values, and booleans like `privileged` cannot be substituted at
all. Merge semantics are OR/union, so a single feature declaring both DinD's
`privileged: true` + named volumes and DooD's host-socket bind mount would apply
**all** of them unconditionally — and the DooD socket mount, applied on a host
without Docker, creates a directory at `/var/run/docker.sock` and corrupts the
host. This is exactly why the upstream project ships `docker-in-docker` and
`docker-outside-of-docker` as two features; DevFeats mirrors that split.

`install-docker` therefore commits to the engine shape: `privileged: true`,
`init: true`, named volumes for `/var/lib/docker` and `/var/lib/containerd`, and
a daemon-starting entrypoint. Standalone (non-devcontainer) installs never read
these fields, so the same feature serves bare-host installs as `mode=host`.

## Mode resolution

`mode=auto` (default) resolves to `dind` during a devcontainer build (detected
via `os__is_devcontainer_build`, the four spec env vars) and `host` otherwise.
`host`/`dind` can be forced.

## Install method: package-first, binary fallback

The framework's `METHOD=auto` resolver is binary-first, which is wrong for a
daemon: Docker's static tarball ships **no systemd unit** and no automatic
security updates, and upstream recommends the package manager. The
`__resolve_method` hook overrides this to prefer:

1. `upstream-package` — Docker's official repo (`docker-ce`, `docker-ce-cli`,
   `containerd.io`) on apt (Debian/Ubuntu) and dnf/yum (Fedora + RHEL family).
   Repo/key setup is the shared `_internal.docker_ce_repo` block in
   `metadata.shared.yaml`.
2. `package` — the distro-native `docker` package (Arch, Alpine, openSUSE).
3. `binary` — the static tarball from `download.docker.com`, last resort
   (air-gapped or repo-less platforms), reachable explicitly via `method=binary`.

Under `method=binary` + host mode the feature **generates the systemd units**
(`containerd.service`, `docker.socket`, `docker.service`) so `enable_service`
works uniformly across methods.

## Version resolution

`resolution: sidecar` scrapes Docker's static index for `docker-<version>.tgz`.
The version URI is **not** context-expanded, so it targets a fixed arch dir
(`x86_64`); Docker releases every arch together, so that version list applies to
all arches. The per-arch `{plat.machine}` (raw `uname -m`, which matches Docker's
static-dir names `x86_64`/`aarch64`/`ppc64le`/`s390x`) is expanded later in the
binary `asset_uri`. The resolved version also pins the `docker-ce` package.

## DinD entrypoint

Deployed only in devcontainer builds. It applies the Moby `hack/dind` container
prep (AppArmor `container=docker`, security/tmp mounts, cgroup-v2 controller
delegation, `mount --make-rshared /`), then starts `containerd` (with an
erofs-snapshotter-disabled `config.toml` — some distros ship `mkfs.erofs` too old
for containerd ≥ 2.3) and `dockerd` (address pool / Azure DNS / ip6tables from
options), and `exec`s the container command. All steps are best-effort with
warnings (e.g. cgroup writes fail on macOS Docker Desktop) so startup proceeds.

## Non-root access

`_options.configure_users` adds the resolved users (`add_current_user`,
`add_remote_user`, `add_container_user`, `add_users`) to the `docker` group.

## Plugins

Buildx and Compose v2 install as repo/distro packages for the package methods and
from GitHub releases for the binary method. Compose Switch (legacy
`docker-compose` → v2) is fetched from GitHub for all methods when enabled. All
GitHub plugin fetches are best-effort (warn, don't abort).
