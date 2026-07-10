# Live Testing

Live testing means running a feature interactively to manually verify it works — useful for exploratory testing, debugging, or confirming behavior before writing formal scenario tests.

## Test Containers

The repository includes a set of `test-<feature-id>` dev containers under `.devcontainer/`. These install the feature from your **local `src/`** build (via the `.devcontainer/.src` symlink, which points to `src/`), so they always reflect your latest `just sync-src` output.

**These containers are auto-generated** from feature metadata by `proman` — do not edit them directly.

To use a test container:

1. Run `just sync-src` to make sure `src/` is current.
2. Open the repository in VS Code.
3. Run **Dev Containers: Reopen in Container** and select `test-<feature-id>`.

The container installs your local feature build at creation time and drops you into a shell where you can verify the feature works as expected.

:::{note}
**`try-<feature-id>` containers are different.** They reference the *published* OCI image (`ghcr.io/quantized8/devfeats/<id>:<version>`) rather than the local build. They exist so end users can quickly try out a released feature without writing their own `devcontainer.json`. They are not useful for testing unreleased local changes.
:::

## Running `install.bash` Directly

For faster iteration, you can run `install.bash` directly in a Docker container without using the devcontainer CLI:

```bash
# Build src/ if not current
just sync-src

# Start a container with the repo mounted
docker run --rm -it \
  -v "$(pwd)/src/install-git:/feat" \
  ubuntu:24.04 \
  bash -c "
    export VERSION=stable
    export METHOD=auto
    export LOG_LEVEL=debug
    export INSTALLER_DIR=/feat
    bash /feat/install.sh
  "
```

Adjust the image, feature path, and env vars as needed. This matches how the devcontainer CLI invokes the installer, minus the devcontainer-specific scaffolding.

## Debugging Install Failures

Feature tests default to `log_level=debug` and `log_file_level=debug` via
`test/features/defaults.shared.yaml` (see {doc}`/dev-guide/tests/features`). `trace` (bash xtrace) is
enabled only per-run via `--xtrace` or CI debug logging.

Set `log_level=trace` to enable `set -x` on the **console** and see every command executed:

```bash
# In devcontainer.json
"features": {
  "ghcr.io/quantized8/devfeats/install-git": {
    "log_level": "trace"
  }
}

# Standalone
export LOG_LEVEL=trace
bash install.sh
```

The `log_file` option redirects all install output to a file in addition to the terminal:

```json
"install-git": {
  "log_level": "debug",
  "log_file": "/tmp/install-git.log"
}
```
