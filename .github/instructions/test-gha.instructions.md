---
description: "Use when working with CI test workflows (.github/workflows/test*.yaml), the install-os-pkg manifest dry-run tests (test/install-os-pkg/dry-run/), or fail scenario scripts (test/**/fail_scenarios.sh, test/run-fail-scenarios.sh). Covers macOS GHA runner behaviour, macOS native feature scenarios, dry-run test structure, adding dry-run cases, fail-scenario conventions, and CI trigger logic."
applyTo: "test/install-os-pkg/dry-run/**, test/**/fail_scenarios.sh, test/run-fail-scenarios.sh, .github/workflows/test*.yaml"
---

# CI, macOS GHA Runner, and Supplementary Tests

## CI Workflow Overview

| Workflow | File | Trigger | Runs on |
|---|---|---|---|
| Feature scenario tests (Linux) | `test.yaml` | push/PR (changed features), manual | ubuntu-latest |
| Feature scenario tests (macOS) | `test-macos.yaml` | push/PR (changed features with macOS scenarios), manual | macos-latest |
| Lib unit tests | `test-unit.yaml` | push/PR touching `lib/**` or `test/unit/**`, manual | ubuntu-latest + macos-latest + linux containers |
| Schema validation | `validate.yml` | PR, manual | ubuntu-latest |
| Lint | `lint.yaml` | push, PR | ubuntu-latest |
| Release | `release.yaml` | manual only | ubuntu-latest |

All workflows run `bash sync-lib.sh` as their first step.

## macOS GHA Runner

Unit tests (`test-unit.yaml`) run on `ubuntu-latest`, `macos-latest`, and several Linux distribution containers. Feature scenario tests that use Docker run only on `ubuntu-latest` — macOS GHA runners cannot run Docker containers.

Features that require a real macOS environment (e.g. `install-homebrew`) use a separate workflow (`test-macos.yaml`) that runs native bash scenario scripts directly on a `macos-latest` runner without Docker.

### bash version on macOS

macOS ships bash 3.2 (GNU GPL licence prevents Apple bundling bash 4+). All lib/ modules require bash ≥4. `test/run-unit.sh` handles this automatically:

1. Checks `BASH_VERSINFO[0] < 4`.
2. Tries `/opt/homebrew/bin/bash` (Apple Silicon) then `/usr/local/bin/bash` (Intel).
3. Re-execs itself under the first bash ≥4 found.
4. Prepends that executable's directory to `PATH` so `#!/usr/bin/env bash` sub-scripts (bats-exec-test, bats-exec-suite) also resolve to bash ≥4.

The GHA `macos-latest` runner does **not** have bash ≥4 pre-installed. `test-unit.yaml` adds an explicit step:

```yaml
- name: Install bash ≥4 (macOS)
  if: runner.os == 'macOS'
  run: brew install bash
```

For local development: `brew install bash`.

### macOS-specific test behaviour

macOS has no `/etc/os-release`, so kernel/platform/distro detection uses `uname -s` fallbacks. Expected values for macOS-targeting unit tests:

| Function | macOS return value |
|---|---|
| `os::kernel` | `Darwin` |
| `os::platform` | `macos` |
| `os::id` | *(empty — no os-release)* |
| `os::font_dir` (as root) | `/Library/Fonts` |
| `os::font_dir` (non-root, no `$XDG_DATA_HOME`) | `${HOME}/Library/Fonts` |

### `shell::detect_bashrc` / `shell::detect_zshdir` on macOS

These functions probe binary paths using `strings`. On macOS, `strings` may return different paths than on Linux. Tests exercising these functions should use `create_fake_bin "strings" "..."` to control the probe output rather than relying on the host.

### Trigger unit tests manually on macOS

```bash
# Local run — re-execs with Homebrew bash automatically
bash test/run-unit.sh

# Watch CI run
gh run watch
```

## macOS Feature Scenarios

`test-macos.yaml` runs feature tests that require a real macOS environment. These scenarios run native bash scripts directly on a `macos-latest` runner — no Docker, no devcontainer CLI.

### Directory structure

```
test/<feature>/macos/
  <scenario>.sh         native bash scenario script
test/lib/
  macos-test-lib.sh     check() / fail_check() / reportResults() / shellenv_block_cleanup()
```

### Script anatomy

Scenario scripts source `test/lib/macos-test-lib.sh` (not `dev-container-features-test-lib`). The repo root is passed as positional argument `$1`. The `check` / `reportResults` API is identical to devcontainer CLI scenarios:

```bash
#!/usr/bin/env bash
set -e
REPO_ROOT="$1"
source "${REPO_ROOT}/test/lib/macos-test-lib.sh"

# Run the installer directly
bash "${REPO_ROOT}/src/install-homebrew/install.sh"

check "brew binary present"     test -f "$(brew --prefix)/bin/brew"
check "brew --version succeeds" "$(brew --prefix)/bin/brew" --version

# Negative check
fail_check "brew not writable by root" test -w "$(brew --prefix)/bin/brew"

reportResults
```

`test/lib/macos-test-lib.sh` additional API:
- `fail_check "label" <cmd>` — passes when `<cmd>` exits **non-zero** (inverse of `check`)
- `shellenv_block_cleanup <file>` — removes `install-homebrew` shellenv blocks from a dotfile in-place; useful in `trap ... EXIT` cleanup

### Running macOS scenarios locally

```bash
# All macOS scenarios for a feature
bash test/run-macos.sh <feature>

# Single scenario
bash test/run-macos.sh <feature> --filter <scenario_name>
```

### CI discovery

`test-macos.yaml` automatically discovers features that have at least one file under `test/<feature>/macos/*.sh`. On push/PR, only features with both macOS scenarios AND changed files under `src/<feature>/` or `test/<feature>/` are tested. On `workflow_dispatch`, all features with macOS scenarios are tested.

No changes to `test-macos.yaml` are needed when adding a new macOS scenario — discovery is fully automatic.

## install-os-pkg Dry-Run Tests

`test/install-os-pkg/dry-run/` is a standalone test suite that verifies manifest parsing and package resolution without a full devcontainer build. It mounts the repo into a plain Docker container and runs `run.sh` inside it.

### Directory structure

```
test/install-os-pkg/dry-run/
  run.sh                        test runner (executed inside Docker)
  cases/
    <case-name>/
      manifest.txt              manifest content to parse
      debian.expected           expected resolved packages for platform=debian
      alpine.expected           expected resolved packages for platform=alpine
      rhel.expected             expected resolved packages for platform=rhel
      macos.expected            expected resolved packages for platform=macos
      ...
```

- Each `.expected` file lists resolved package names, one per line, **sorted alphabetically**.
- An **empty** `.expected` file asserts that zero packages are resolved on that platform.
- **Omitting** a `<platform-id>.expected` file marks the case as SKIP on that platform.

### Running dry-run tests

```bash
# Debian / Ubuntu
docker run --rm -v "$(pwd):/repo" debian:latest \
  bash /repo/test/install-os-pkg/dry-run/run.sh

# Alpine
docker run --rm -v "$(pwd):/repo" alpine:latest \
  bash /repo/test/install-os-pkg/dry-run/run.sh

# Fedora / RHEL
docker run --rm -v "$(pwd):/repo" fedora:latest \
  bash /repo/test/install-os-pkg/dry-run/run.sh

# opensuse, arch also supported
docker run --rm -v "$(pwd):/repo" opensuse/leap:latest \
  bash /repo/test/install-os-pkg/dry-run/run.sh

# Override platform detection (useful on macOS host where /etc/os-release is absent)
docker run --rm -e PLATFORM_ID=debian -v "$(pwd):/repo" debian:latest \
  bash /repo/test/install-os-pkg/dry-run/run.sh
```

### Adding a dry-run test case

1. Create `test/install-os-pkg/dry-run/cases/<case-name>/`.
2. Add `manifest.txt` with the manifest content to test.
3. Add one `<platform-id>.expected` file per distro you want to cover. Sort the package names (`sort` the list before writing).
4. Run the dry-run suite against the relevant distro image(s) to verify.

Example — a manifest with a selector block:

```
# manifest.txt
curl
[pm=apt]
  apt-specific-pkg
```

```
# debian.expected
apt-specific-pkg
curl
```

```
# alpine.expected
curl
```

CI (`test.yaml`) runs the dry-run suite in a matrix across all supported distro images whenever `install-os-pkg` is in the discovered changed-feature set.

## Fail Scenarios

The devcontainer CLI cannot assert that a feature install exits non-zero. `fail_scenarios.sh` fills this gap.

### Writing `fail_scenarios.sh`

```bash
# test/<feature>/fail_scenarios.sh
# Each fail_scenario call expects scripts/install.sh to exit non-zero.

fail_scenario "invalid version string" \
    VERSION=bad_value

fail_scenario "network required but unavailable" \
    --network none \
    ANOTHER_VAR=value
```

DSL arguments:
- `KEY=VALUE` — passed as environment variables to the install script.
- `--network none` — network-isolated container. The runner pre-builds a base image with the feature's OS-package dependencies already installed so only the install step itself lacks network access.

### Running fail scenarios

```bash
bash test/run-fail-scenarios.sh <feature>
```

### CI integration

`test.yaml` runs `bash test/run-fail-scenarios.sh <feature>` as a separate job step after the main scenario matrix, for any feature that has a `test/<feature>/fail_scenarios.sh` file. No changes to `test.yaml` are needed when adding a new `fail_scenarios.sh`.

## CI Trigger Logic

### Feature test discovery

`test.yaml` uses a `discover` job to build the feature matrix:

- **push / PR**: only features with changed files under `src/<feature>/` or `test/<feature>/`
- **workflow_dispatch**: all features under `src/`

No changes to `test.yaml` are needed when adding a new feature — discovery is automatic once a `devcontainer-feature.json` and `test/` directory exist.

### Unit test triggers

`test-unit.yaml` triggers on any change to `lib/**` or `test/unit/**`. It runs the full suite across three job groups — no per-module discovery:

| Job | Runs on | Notes |
|---|---|---|
| `unit-native` | ubuntu-latest + macos-latest | Installs bash ≥4 on macOS via `brew install bash` |
| `unit-linux` | debian:bookworm, fedora:latest, rockylinux:9 containers | Validates glibc distro compatibility |
| `unit-alpine` | alpine:3.20 container (ubuntu-latest host) | Validates musl/Alpine compatibility |

`fail-fast: false` ensures a failure in one matrix cell does not cancel the rest.

A lefthook **pre-push** hook also runs the full bats suite locally when `lib/` or `test/unit/` files are changed:

```yaml
# lefthook.yml excerpt
pre-push:
  commands:
    unit-tests:
      glob: "{lib/**,test/unit/**}"
      run: bash test/run-unit.sh
```

### Manual dispatch

```bash
# Trigger all feature tests
gh workflow run "CI - Test Features"

# Trigger unit tests
gh workflow run "Unit Tests"

# Watch a run
gh run watch

# List recent runs
gh run list --workflow "Unit Tests"
```
