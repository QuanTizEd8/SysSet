# install-docker-dood — design notes

Installs the Docker **CLI only** and forwards the **host's** Docker socket into
the container (Docker-outside-of-Docker). For a full nested engine, use the
companion [`install-docker`](../install-docker/) feature.

## Why a separate feature

See [`install-docker/notes.md`](../install-docker/notes.md#why-dind-and-dood-are-separate-features):
a feature's static `devcontainer-feature.json` config cannot vary by option
value, and DooD's shape (a host-socket **bind mount**, `securityOpt=label=disable`,
**no** privilege) is mutually exclusive with DinD's (privileged + named volumes).
DooD also cannot `dependsOn` `install-docker` to reuse its CLI, because that would
re-inherit `install-docker`'s privileged/volume config — so this feature installs
its own client.

## Static config

- `mounts`: host `/var/run/docker.sock` → container `/var/run/docker-host.sock`
  (bind). Users override this in `devcontainer.json` for rootless or relocated
  host sockets (e.g. `/run/user/<uid>/docker.sock`).
- `securityOpt: [label=disable]`: SELinux relabel off so the container can use
  the mounted socket.
- `entrypoint`: forwards the socket at container start.

## Socket forwarding (entrypoint)

At container start the entrypoint exposes `socket_path` at `target_socket`:

- If a non-root group owns the socket and that GID is free in the container, the
  container `docker` group's GID is realigned to it and the socket is symlinked —
  group members get direct access.
- If the socket is root-owned (common with rootful host Docker) it is proxied
  with `socat` (`mode=660,group=docker`) so `docker`-group members can connect.
- With `enable_nonroot=false`, only root gets access (a plain symlink).

## Install method

Same package-first resolution as `install-docker` (`__resolve_method` override):
`docker-ce-cli` from Docker's repo (apt/dnf/yum, shared `_internal.docker_ce_repo`
block), the distro CLI package otherwise (Alpine `docker-cli`; Arch/openSUSE
`docker`), or just the `docker` client from the static tarball. Version
resolution, plugins, and the `docker` group setup mirror `install-docker`.
