---
description: "Use when writing or editing devcontainer feature test scenarios, scenarios.json files, scenario assertion scripts, or test Dockerfiles under test/. Covers scenarios.json format, scenario script anatomy, assertion patterns, Dockerfiles, and fail scenarios."
applyTo: "test/*/scenarios.json, test/*/*.sh, test/**/Dockerfile"
---

# Feature Scenario Tests (devcontainer CLI)

Each feature test builds a dev container, installs the feature, then runs an assertion script inside the running container. Tests live under `test/<feature>/` and are driven by the devcontainer CLI.

## Directory Layout

```
test/<feature>/
  scenarios.json           Test matrix — one entry per scenario (required)
  <scenario>.sh            Assertion script (runs inside the container)
  <scenario>/              Build context — only present when a Dockerfile is needed
    Dockerfile
    <other files>
```

## `scenarios.json` Format

```jsonc
{
  // Use "image" when no pre-condition state is needed (no <scenario>/ directory required).
  "<scenario_name>": {
    "image": "ubuntu:latest",
    "features": {
      "<feature-dir>": { "<option>": "<value>" }
    }
  },

  // Use "build" when the base image needs extra RUN steps.
  "<other_scenario>": {
    "remoteUser": "vscode",
    "build": { "dockerfile": "Dockerfile" },
    "features": {
      "<feature-dir>": { "<option>": "<value>" }
    }
  }
}
```

- The feature key in `"features"` is the **directory name** under `src/` (equals the feature `"id"`).
- Scenario names must exactly match the `.sh` filename (without `.sh`).
- Use `"image"` for plain base images — no `<scenario>/` directory required.
- Use `"build"` when the image needs pre-condition setup via Dockerfile; keep the Dockerfile in `<scenario>/`.
- `"remoteUser"` is optional; set it only when the scenario tests user-specific behaviour.

## Scenario Script Anatomy

```bash
#!/bin/bash
# One-line description of what this scenario verifies.
set -e

source dev-container-features-test-lib

# --- section heading ---
check "binary on PATH"        which mytool
check "version is correct"    bash -c "mytool --version | grep '1.2.3'"
check "config dir created"    test -d /home/vscode/.config/mytool

reportResults
```

- `check "<label>" <cmd>` — passes if `<cmd>` exits 0.
- `reportResults` — required at the end; exits non-zero if any check failed.
- Group related checks under section-heading comments (`# --- foo ---`).

## Common Assertion Patterns

```bash
# Tool on PATH
check "pixi on PATH"                which pixi

# Version match
check "version correct"             bash -c "pixi --version | grep '0.66'"

# File / directory existence
check "config dir exists"           test -d /home/vscode/.config/starship
check "binary is executable"        test -x /usr/local/bin/mytool
check "file is non-empty"           test -s /etc/myconf

# File content
check "contains entry"              grep -Fq "export PATH" /root/.bashrc
check "contains pattern"            grep -q "PATTERN" /path/to/file

# Value comparison (compound expression — use bash -c)
check "uid is 1000"                 bash -c '[ "$(id -u vscode)" = "1000" ]'
check "shell is zsh"                bash -c 'getent passwd vscode | cut -d: -f7 | grep -q zsh'

# Negative assertion
check "tree not installed"          bash -c '! command -v tree'
check "old user gone"               bash -c '! id old_user > /dev/null 2>&1'

# Exact count
check "exactly one activation line" bash -c '[ "$(grep -Fc "conda.sh" ~/.bashrc)" -eq 1 ]'

# As a specific user
check "plugin loaded"               bash -c "su -l vscode -c 'zsh -i -c \"omz plugin list\"' | grep autojump"
```

Use `grep -Fq` (fixed string) rather than `grep -q` (regex) when checking literal file content — avoids regex metacharacters in paths broadening the match.

## Dockerfiles

Only create a `<scenario>/Dockerfile` when the base image needs extra `RUN` instructions to establish a pre-condition state. Never create a Dockerfile that contains only a `FROM` line — use `"image"` in `scenarios.json` instead.

```dockerfile
# Scenario: reinstall — test idempotency against an existing installation
FROM ubuntu:latest
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/*
```

```dockerfile
# Scenario: replace_existing — conflicting UID already occupied
FROM ubuntu:latest
RUN useradd --uid 1000 --user-group --no-create-home --shell /bin/sh old_user
```

Additional files in `<scenario>/` land flat in the temp `.devcontainer/` directory and are `COPY`-addressable by their path relative to `<scenario>/`:

```dockerfile
COPY setup.sh /tmp/setup.sh
RUN bash /tmp/setup.sh
```

## Build Arguments

Pass host environment variables into Docker build args:

```jsonc
"my_scenario": {
  "build": {
    "dockerfile": "Dockerfile",
    "args": { "GITHUB_TOKEN": "${localEnv:GITHUB_TOKEN}" }
  }
}
```

```dockerfile
ARG GITHUB_TOKEN
FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
```

`${localEnv:VAR}` is resolved from the shell running the devcontainer CLI. Missing values become empty strings.

## Fail Scenarios

The devcontainer CLI cannot assert that a feature install exits non-zero. Use `fail_scenarios.sh` for expected-failure cases:

```bash
# test/<feature>/fail_scenarios.sh
# Each call expects scripts/install.sh to exit non-zero.

fail_scenario "invalid version string" \
    VERSION=bad_value

fail_scenario "network required but unavailable" \
    --network none
```

DSL:
- `KEY=VALUE` — environment variables passed to the install script.
- `--network none` — network-isolated container; the runner pre-builds an image with the feature's dependencies pre-installed so only the install step itself is isolated.

Run with: `bash test/run.sh feature <feature>` (runs fail scenarios together with all other scenarios). To run fail scenarios in isolation: `bash test/run-fail-scenarios.sh <feature>`.

## Running Tests Locally

```bash
# Sync generated files first
bash sync-lib.sh

# All scenarios + fail scenarios for a feature
bash test/run.sh feature <feature>

# Single scenario only (no fail scenarios)
devcontainer features test -f <feature> --skip-autogenerated --project-folder . --filter <scenario_name>
```

Always use `--project-folder .` (repo root). The `.devcontainer/_src → ../src` symlink lets the CLI resolve features from the root.

Prerequisites: Docker running, Node.js, devcontainer CLI (`npm install -g @devcontainers/cli`).

## Notes

- **Use absolute paths in checks.** Containers may have a sparse `PATH`. Prefer `/opt/conda/bin/conda` over bare `conda`.
- **One thing per scenario.** A scenario named after its specific configuration (`strict_channel_priority`, `update_existing`) is far easier to debug than a combined one.
- **`true` is a valid check command** when you only need to assert the feature exited cleanly: `check "installed cleanly" true`.

---

## macOS Native Scenarios

For features that install on macOS (e.g. `install-homebrew`), use native bash scripts that run directly on a macOS runner — no Docker, no devcontainer CLI.

### Directory structure

```
test/<feature>/macos/
  <scenario>.sh         native bash scenario script
test/lib/
  assert.sh             shared assertion library for macOS and dist scripts
```

### Script anatomy

macOS scenarios source `test/lib/assert.sh` instead of `dev-container-features-test-lib`. The `check` / `reportResults` API is identical. The repo root is passed as positional argument `$1`:

```bash
#!/usr/bin/env bash
set -e
REPO_ROOT="$1"
source "${REPO_ROOT}/test/lib/assert.sh"

_BREW_PREFIX="$(brew --prefix 2>/dev/null)"

# Run the installer
bash "${REPO_ROOT}/src/install-homebrew/install.sh"

check "brew binary present"     test -f "${_BREW_PREFIX}/bin/brew"
check "brew --version succeeds" "${_BREW_PREFIX}/bin/brew" --version

reportResults
```

`test/lib/assert.sh` provides the full API:
- `check "label" <cmd>` — passes if `<cmd>` exits 0
- `fail_check "label" <cmd>` — passes if `<cmd>` exits **non-zero** (for asserting expected failures)
- `reportResults` — prints summary and exits 1 if any check failed
- `shellenv_block_cleanup <file>` — removes `install-homebrew` shellenv blocks from a dotfile; use in a `trap ... EXIT` to clean up written dotfiles

### Cleanup via trap

macOS scenarios that write dotfiles should clean up after themselves:

```bash
_cleanup() {
  for f in ~/.bash_profile ~/.bashrc ~/.zprofile ~/.zshrc; do
    shellenv_block_cleanup "$f"
  done
}
trap _cleanup EXIT
```

### Running macOS scenarios locally

```bash
# All macOS scenarios for a feature (requires macOS)
bash test/run-macos.sh <feature>

# Single scenario
bash test/run-macos.sh <feature> --filter <scenario_name>
```

CI runs these automatically via `test-macos.yaml` on a `macos-latest` runner. No `scenarios.json` entry is needed — `run-macos.sh` discovers scenario scripts directly from the filesystem.

## Further Reading

- `docs/dev-guide/testing.md` — full narrative guide with examples
- `test-gha.instructions.md` — CI workflow triggers, discover job, macOS runner
