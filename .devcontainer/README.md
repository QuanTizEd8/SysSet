## Dev Container

`.devcontainer/devcontainer.json` uses `mcr.microsoft.com/devcontainers/javascript-node:1-20-bookworm` with docker-in-docker.
The `_src → ../src` symlink allows the devcontainer CLI (which only looks inside `.devcontainer/`) to find features during local development.
