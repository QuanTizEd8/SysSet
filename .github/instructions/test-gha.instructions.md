---
description: "Use when working with CI/CD workflows (.github/workflows/cicd.yaml, ci.yaml, cd.yaml), the install-os-pkg manifest dry-run tests (test/install-os-pkg/dry-run/), or fail scenario scripts (test/**/fail_scenarios.sh, test/run-fail-scenarios.sh). Covers macOS GHA runner behaviour, macOS native feature scenarios, dry-run test structure, adding dry-run cases, fail-scenario conventions, CI trigger logic, and how to inspect workflow run results and logs."
applyTo: "test/install-os-pkg/dry-run/**, test/**/fail_scenarios.sh, test/run-fail-scenarios.sh, .github/workflows/*.yaml"
---

# CI, macOS GHA Runner, and Supplementary Tests

## CI Workflow Overview

| Workflow | File | Trigger | Purpose |
|---|---|---|---|
| CI/CD Orchestrator | `cicd.yaml` | push/PR, `v*` tag push, `workflow_dispatch` | Runs `detect` → calls `ci.yaml`, then `cd.yaml` on release |
| Continuous Integration | `ci.yaml` | `workflow_call` from `cicd.yaml`, standalone `workflow_dispatch` | All lint/validate/unit/feature/dist tests |
| Continuous Deployment | `cd.yaml` | `workflow_call` from `cicd.yaml`, standalone `workflow_dispatch` | Publish to GHCR + GitHub Release |

All jobs run `bash sync-lib.sh` as an early step.

## macOS GHA Runner

Unit tests (`test-unit.yaml`) run on `ubuntu-latest`, `macos-latest`, and several Linux distribution containers. Feature scenario tests that use Docker run only on `ubuntu-latest` — macOS GHA runners cannot run Docker containers.

Features that require a real macOS environment (e.g. `install-homebrew`) use a separate workflow (`test-macos.yaml`) that runs native bash scenario scripts directly on a `macos-latest` runner without Docker.

### bash version on macOS

macOS ships bash 3.2 (GNU GPL licence prevents Apple bundling bash 4+). All lib/ modules require bash ≥4. `test/run-unit.sh` handles this automatically:

1. Checks `BASH_VERSINFO[0] < 4`.
2. Tries `/opt/homebrew/bin/bash` (Apple Silicon) then `/usr/local/bin/bash` (Intel).
3. Re-execs itself under the first bash ≥4 found.
4. Prepends that executable's directory to `PATH` so `#!/usr/bin/env bash` sub-scripts (bats-exec-test, bats-exec-suite) also resolve to bash ≥4.

The GHA `macos-latest` runner does **not** have bash ≥4 pre-installed. The `unit-native` job in `ci.yaml` adds an explicit step:

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
| `os__kernel` | `Darwin` |
| `os__platform` | `macos` |
| `os__id` | *(empty — no os-release)* |
| `os__font_dir` (as root) | `/Library/Fonts` |
| `os__font_dir` (non-root, no `$XDG_DATA_HOME`) | `${HOME}/Library/Fonts` |

### `shell__detect_bashrc` / `shell__detect_zshdir` on macOS

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
  assert.sh             check() / fail_check() / reportResults() / shellenv_block_cleanup()
```

### Script anatomy

Scenario scripts source `test/lib/assert.sh` (not `dev-container-features-test-lib`). The repo root is passed as positional argument `$1`. The `check` / `reportResults` API is identical to devcontainer CLI scenarios:

```bash
#!/usr/bin/env bash
set -e
REPO_ROOT="$1"
source "${REPO_ROOT}/test/lib/assert.sh"

# Run the installer directly
bash "${REPO_ROOT}/src/install-homebrew/install.sh"

check "brew binary present"     test -f "$(brew --prefix)/bin/brew"
check "brew --version succeeds" "$(brew --prefix)/bin/brew" --version

# Negative check
fail_check "brew not writable by root" test -w "$(brew --prefix)/bin/brew"

reportResults
```

`test/lib/assert.sh` additional API:
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

The `test-macos` job in `ci.yaml` automatically discovers features that have at least one file under `test/<feature>/macos/*.sh`. On push/PR, only features with both macOS scenarios AND changed files under `src/<feature>/` or `test/<feature>/` are tested. On `workflow_dispatch` (including when called from `cicd.yaml` with `is_force=true`), all features with macOS scenarios are tested.

No changes to `ci.yaml` are needed when adding a new macOS scenario — discovery is fully automatic.

## install-os-pkg Dry-Run Tests

`test/install-os-pkg/dry-run/` is a standalone test suite that verifies manifest parsing and package resolution without a full devcontainer build. It mounts the repo into a plain Docker container and runs `run.sh` inside it.

### Directory structure

```
test/install-os-pkg/dry-run/
  run.sh                        test runner (executed inside Docker)
  cases/
    <case-name>/
      manifest.yaml              manifest content to parse
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
2. Add `manifest.yaml` with the manifest content to test.
3. Add one `<platform-id>.expected` file per distro you want to cover. Sort the package names (`sort` the list before writing).
4. Run the dry-run suite against the relevant distro image(s) to verify.

Example — a manifest with a selector block:

```yaml
# manifest.yaml
packages:
  - curl
apt:
  packages:
    - apt-specific-pkg
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

CI (`ci.yaml`) runs the dry-run suite in a matrix across all supported distro images whenever `install-os-pkg` is in the discovered changed-feature set.

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

The `test-features` job in `ci.yaml` runs `bash test/run.sh feature <feature>` as a single step that covers both the scenario matrix and fail scenarios. No changes to `ci.yaml` are needed when adding a new `fail_scenarios.sh`.

## CI Trigger Logic

### Change detection

`cicd.yaml` runs a `detect` job on every event that computes per-job run flags from the changed-file diff:

| Changed path(s) | Flag set / Jobs gated |
|---|---|
| `*.sh`, `*.bash`, `*.bats` | `run_lint` → `lint` |
| `src/**/devcontainer-feature.json` | `run_validate` → `validate` |
| `lib/**`, `test/unit/**` | `run_unit` → `unit-native`, `unit-linux` |
| `src/<f>/` or `test/<f>/` | `run_features`, `features[]` → `test-features` matrix |
| macOS-capable feature in `features[]` | `run_macos`, `macos_features[]` → `test-macos` matrix |
| `install-os-pkg` in `features[]` | `run_features` → `test-os-pkg` (6-distro matrix) |
| `get.sh`, `sysset.sh`, `build-artifacts.sh`, `src/**`, `lib/**`, `test/dist/**` | `run_dist` → `test-dist-*` |

On `workflow_dispatch` or a `v*` tag push, `is_force=true` overrides all flags to `true` regardless of diff. First push to a new branch (zero-SHA `before`) also sets `is_force=true` as a safe fallback.

### Feature test and macOS test discovery

The `detect` job discovers changed features by intersecting all `ls src` names against `src/<f>/` or `test/<f>/` diff paths. macOS-eligible features are found by scanning `test/<feature>/macos/*.sh`.

- **push/PR**: only changed features that exist under `src/` and `test/`
- **`workflow_dispatch` or tag push**: all features

No changes to any workflow file are needed when adding a new feature or new macOS scenarios — discovery is automatic.

### Unit test triggers

The `unit-native` and `unit-linux` jobs in `ci.yaml` run when `lib/**` or `test/unit/**` are changed. Two job groups run in parallel — no per-module discovery:

| Job | Runs on | Notes |
|---|---|---|
| `unit-native` | ubuntu-latest + macos-latest | Installs bash ≥4 on macOS via `brew install bash` |
| `unit-linux` | debian:bookworm, fedora:latest, rockylinux:9, alpine:3.20 containers | Validates glibc and musl compatibility |

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

### Release and publish

`is_release=true` is set when the trigger is a `v*` tag push or a `workflow_dispatch` with a `tag` input. The `cd` job in `cicd.yaml` runs only when `is_release=true` AND the `ci` job result is `success`. CD can also be triggered standalone:

```bash
# Publish without tests (e.g. hotfix or re-deploy)
gh workflow run "CD" --field tag=v1.2.3
```

## Monitoring CI Runs (for Agents)

Use the `gh` CLI to inspect workflow runs, job results, and logs. MCP GitHub tools do not expose workflow-run APIs; use `gh` for everything run/job/log related.

### Workflow and run structure

`cicd.yaml` is the orchestrator — the only file with event triggers. Its `ci` and `cd` jobs call `ci.yaml` and `cd.yaml` via `workflow_call`. The called workflows' jobs appear as individual entries **inside the same parent run** (no separate nested runs). A typical run contains:

- `detect` — always runs; sets flags
- `ci / setup`, `ci / lint`, `ci / validate`, `ci / unit-native (ubuntu-latest)`, `ci / unit-native (macos-latest)`, `ci / unit-linux (debian)`, ...
- `ci / test-features (install-shell)`, `ci / test-features (install-pixi)`, ... (matrix)
- `ci / test-macos (install-homebrew)`, ... (matrix, if applicable)
- `ci / test-dist-build`, `ci / test-dist-sysset (debian)`, ...
- `cd / publish` — only on release triggers

### Listing and identifying runs

```bash
# List recent runs (all workflows)
gh run list --limit 10

# List runs for the orchestrator
gh run list --workflow "CI/CD" --limit 10

# Filter by branch or status
gh run list --workflow "CI/CD" --branch main --status failure --limit 5
```

Output columns: run ID, status/conclusion, workflow name, branch, event, elapsed time.

### Viewing run summary and job results

```bash
# Show run summary: all jobs, their status, and job IDs
gh run view <run-id>

# Get job list as JSON (includes job IDs, names, conclusions, steps)
gh run view <run-id> --json jobs

# Get full run metadata as JSON
gh run view <run-id> --json jobs,status,conclusion,event,headBranch,headSha
```

Use `--json jobs` to map job names to numeric IDs for log retrieval.

### Fetching logs

```bash
# Stream all logs for the entire run (verbose for large matrix runs)
gh run view <run-id> --log

# Fetch only the failed steps' logs — fastest way to find the root cause
gh run view <run-id> --log-failed

# Fetch logs for a specific job by job ID
gh run view <run-id> --job <job-id> --log
```

To look up a job ID by name:

```bash
# Find the database ID for a job matching a name substring
gh run view <run-id> --json jobs \
  | jq -r '.jobs[] | select(.name | test("Test install-shell")) | .databaseId'
```

Then fetch its logs:

```bash
gh run view <run-id> --job <job-id> --log
```

### Watching a run in progress

```bash
# Watch the most recent run
gh run watch

# Watch a specific run
gh run watch <run-id>
```

### Triggering and re-running

```bash
# Run the full CI/CD suite (no publish)
gh workflow run "CI/CD"

# Run with a release tag (triggers publish if CI passes)
gh workflow run "CI/CD" --field tag=v1.2.3

# Run CI tests only (standalone, discovers all features automatically)
gh workflow run "CI"

# Publish only (no tests) — useful for hotfix or re-deploy
gh workflow run "CD" --field tag=v1.2.3

# Re-run only the failed jobs in a run
gh run rerun <run-id> --failed
```

### Using the GitHub REST API

For finer-grained access (e.g. downloading step-level logs as raw text):

```bash
# List all jobs for a run (returns IDs, names, steps, conclusions)
gh api repos/quantized8/sysset/actions/runs/<run-id>/jobs

# Get the log redirect URL for a specific job
gh api repos/quantized8/sysset/actions/jobs/<job-id>/logs
```

### MCP GitHub tools (for agents using MCP)

MCP tools do not expose workflow-run APIs. Use them only to look up context that correlates with a run:

- `mcp_github_list_pull_requests` / `mcp_io_github_git_list_pull_requests` — find the PR associated with a branch
- `mcp_github_get_commit` / `mcp_io_github_git_get_commit` — inspect the commit that triggered a run
- `mcp_github_list_commits` / `mcp_io_github_git_list_commits` — find recent commits on a branch

For all workflow-run and job-log operations, use `gh` CLI (`gh run list`, `gh run view`, `gh run watch`, `gh api`) rather than MCP tools.
