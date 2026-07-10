# CI/CD Pipelines

The CI/CD stack lives under `.github/workflows/`. All workflows are reusable and called from a single orchestrator.

## Workflow Overview

| File | Type | Purpose |
|------|------|---------|
| `main.yaml` | Orchestrator | Detects what to run, calls all reusable workflows |
| `lint.yaml` | Reusable | Shell format-check + shellcheck, Python format-check + ruff, and devcontainer-feature.json schema validation |
| `test-lib.yaml` | Reusable | Library unit tests (BATS) in container matrix |
| `test-dev.yaml` | Reusable | Python unit tests for proman (pytest) |
| `test-install.yaml` | Reusable | Install-framework tests (BATS over synced `install.bash`) |
| `test-features.yaml` | Reusable | Feature scenario tests (devcontainer + standalone + macOS) |
| `build-devcontainer.yaml` | Reusable | Build and publish the CI devcontainer image |
| `build-docs.yaml` | Reusable | Build Sphinx docs |
| `build-features.yaml` | Reusable | Build feature release tarballs |
| `deploy.yaml` | Reusable | Deploy features to GHCR and GitHub Releases |

## Main Pipeline (`main.yaml`)

Triggers: `push`, `pull_request`, `workflow_dispatch`.

On every run, an `init` job installs proman (`pip install .dev/lib`) and runs `proman-cicd-detect`, which outputs a single JSON config blob consumed by all downstream jobs. The config encodes:
- Which jobs to enable (based on changed file paths and dispatch inputs)
- The feature and macOS test matrices
- Whether the devcontainer image needs rebuilding
- Which features are eligible for deployment (untagged versions)

### Change Detection

Jobs are enabled/disabled based on which paths changed. Glob patterns are configured in `.config/proman/ci.yaml` → `triggers`:

| Changed paths | Jobs enabled |
|---------------|-------------|
| `**/*.sh`, `**/*.bash`, `**/*.bats` | lint (shell) |
| `**/metadata.yaml`, `**/*.schema.json` | lint (schema validation) |
| `lib/*.sh`, `lib/*.bash`, `lib/*.json`, `test/lib/**` | `test-lib` |
| `lib/**`, `features/install.sh`, or `features/metadata.shared.yaml` | `test-features` for **all** features |
| `features/<id>/` or `test/features/<id>/` | `test-features` for **that feature only** |
| `features/install.tmpl.bash`, `lib/**`, or `test/install/**` | `test-install` (install-framework) |
| `.devcontainer/.dev/**` | `build-devcontainer` |
| `docs/**`, `features/**`, `lib/**`, `.config/proman/docs.yaml` | `build-docs` |
| `.dev/lib/**`, `.config/proman/**`, `test/proman/**` | `test-dev` (Python tests) |

On `workflow_dispatch`, all jobs run unconditionally regardless of changed paths.

### Manual Triggers

```bash
# Trigger the full pipeline on the current branch
gh workflow run "Main Pipeline"

# Trigger with specific features only
gh workflow run "Main Pipeline" \
  --field features="install-git,install-pixi" \
  --field run_macos=false

# Watch the most recent run
gh run watch

# Stream CI logs after a push
just fetch-gha --commit HEAD

# Stream logs for a specific run ID
just fetch-gha --run 12345678
```

Logs are saved to `.local/logs/gha/<commit-sha>/<run-id>/`:

| File | Contents |
|------|----------|
| `passing.log` | One job name per line (success/skipped) |
| `failing.log` | `job-name --- step-name --- <job-id>.log` per failing step |
| `<job-id>.log` | Full GHA job log (timestamps stripped); debug-level installer output in feature tests |
| `<job-id>.trace.log` | Failed feature-test jobs only: `feat-log-*` artifact (install log at whatever `log_file_level` the job ran with) |

Feature-test job names look like `Test Feature install-git / default_install.ubuntu-stable (linux)` (reusable workflow); artifacts are named `feat-log-<feature>-<scenario-key>-<mode>`. `fetch-gha` resolves the exact artifact name from the job name.

Feature-test jobs run at `log_file_level: debug` by default (see {doc}`/dev-guide/tests/features`),
so a first-time failure's `.trace.log` won't have bash xtrace. To get a trace-level log for a
failing job, re-run it with debug logging enabled — `gh run rerun <run-id> --failed --debug` (or
the "Enable debug logging" checkbox in the GitHub UI re-run dialog) — then `fetch-gha` again once
the re-run finishes; the workflow reads GitHub's `runner.debug` context and automatically bumps
`log_file_level` to `trace` for that run, no other input needed.

Per-scenario install logs are also written during local/CI test runs under
`.local/logs/tests/features/<feature>--<scenario-key>--<mode>.log` (see {doc}`/dev-guide/tests/features`).

### `workflow_dispatch` Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `rebuild_devcontainer` | false | Force devcontainer image rebuild |
| `run_lint` | true | Shell + Python lint |
| `run_validate` | true | devcontainer-feature.json validation |
| `run_python` | true | Python lint + pytest |
| `run_docs` | true | Build docs |
| `run_unit` | true | Library unit tests |
| `run_install` | true | Install-framework unit tests |
| `run_install_linux` | true | Install-framework tests in Linux container matrix |
| `run_lib_linux` | true | Library tests in Linux container matrix |
| `run_lib_macos` | true | Library tests on macOS runner |
| `run_features` | true | Feature scenario tests |
| `features` | (all) | Comma-separated feature IDs to test (blank = all) |
| `run_features_devcontainer` | true | Devcontainer-mode feature tests |
| `run_features_linux` | true | Standalone-Linux-mode feature tests |
| `run_macos` | true | macOS-mode feature tests |
| `macos_features` | (all) | Comma-separated feature IDs for macOS tests |

## CI Jobs

### Lint

Runs `just format-sh-check` and `just lint-sh-check` on all shell files, plus `just format-py-check` and `just lint-py-check` on all Python files. Runs in the devcontainer image.

### Validate

Runs `devcontainers/action` in validate-only mode on `src/` to confirm all `devcontainer-feature.json` files are spec-compliant. Requires `just sync-src` to have run first.

### Library Unit Tests

Two parallel groups:

| Group | How it runs |
|-------|-------------|
| Linux container matrix | ubuntu-latest runner; each environment from `test/lib/scenarios.yaml` runs in its own Docker container (Ubuntu, Debian, Fedora, Rocky, Alpine, openSUSE, Arch) |
| macOS | Native macOS runners; installs bash ≥4 via `brew install bash` before running |

### Install Framework Tests

Runs the install-framework BATS suite (`test/install/*.bats`) against the synced `install.bash` in the Linux container matrix. It exercises the template orchestration helpers (`__resolve_auto_method__`, dependency dispatch, version-input parsing, init resolution order) by sourcing a synced feature installer with its final dispatch call stripped. Requires `just sync-src` to have run.

### Feature Scenario Tests

Runs feature tests via `proman-test-run`. Three sub-modes run in parallel:

- **Devcontainer** (`test-features-devcontainer`): installs via the devcontainer CLI inside a Docker-in-Docker container running the CI devcontainer image. Each scenario matrix entry is an independent job. Before checkout, a cheap `df` check gates the `jlumbroso/free-disk-space` cleanup step behind `free_disk_space.min_avail_gb` (`.config/proman/ci.yaml`, default 15GB) — GH-hosted runners land on one of (at least) two disk layouts, a ~145GB single root partition (~89GB free out of the box) or a split ~72GB root + separate `/mnt` scratch disk (root can start as low as ~19GB free), so the step only runs on the latter. Real job telemetry (`df -h /` after the test step, sampled across ~10 features) shows a single devcontainer-mode scenario consistently consumes only 3-4GB, so 15GB is already a ~4x margin. `free_disk_space.large_packages` defaults to `false` (worst time/space ratio of the action's categories: seven sequential `apt-get remove` calls for the least space freed); flip it on per-run if the other categories aren't enough. The post-test `df -h /` line keeps giving ongoing telemetry to recalibrate `min_avail_gb` further if needed.
- **Standalone Linux** (`test-features-linux`): runs `install.bash` directly in plain Docker containers (standalone mode).
- **macOS** (`test-features-macos`): runs on native `macos-latest` runners for scenarios with `modes: [macos]`.

Scenarios inherit logging defaults from `test/features/defaults.shared.yaml` (`log_level: debug`, `log_file_level: debug`). Each job uploads `.local/logs/tests/features/<feature>--<scenario-key>--<mode>.log` as a `feat-log-*` artifact for post-mortem analysis (see the log table under **Manual Triggers** above).

### Docs Build

Builds the Sphinx site (`just build-docs`) and uploads the result as a GitHub Pages artifact.

### Build Features

Runs `just build-feats` to produce per-feature tarballs in `dist/`. These are uploaded as the `devfeats-dist` artifact and consumed by the deploy workflow.

## Deployment (`deploy.yaml`)

Deployment runs automatically on `push` to `main` when at least one feature has an untagged version. It requires CI to have passed.

### Deploy: GHCR

Uses `devcontainers/action` with `publish-features: "true"` to push each feature (from the synced `src/` artifact) as an OCI image to GHCR. The action generates the tags `:latest`, `:<major>`, `:<major.minor>`, and `:<major.minor.patch>`.

Repo-tagging is disabled (`disable-repo-tagging: "true"`) — the `deploy-gh-release` job handles Git tags.

### Deploy: GitHub Releases

A matrix job runs per feature in `features_to_release`. For each feature:

1. Creates annotated Git tag `<feature-id>/<X.Y.Z>` on the commit.
2. Creates a GitHub Release `<feature-id>/<X.Y.Z>` with the feature tarball as the release asset (`devfeats-<feature-id>.tar.gz`).

### Deploy: Library

The shared bash library is released **independently** of the features by the `deploy-lib-release` job: it creates the Git tag `lib/<X.Y.Z>` and a GitHub Release whose single asset is `devfeats-bashlib.tar.gz` (built by `just build-lib`). The library is **not** published to GHCR.

### Deploy: Docs

The `deploy-gh-pages` job publishes the built docs site to GitHub Pages. It runs as part of the deployment workflow — i.e. on every `push` to `main` that triggers a deploy — not only when docs content changes.

### Release Identity

Each feature has its own independent release identity:

| Artifact | Format |
|----------|--------|
| Git tag | `<feature-id>/<X.Y.Z>` (e.g. `install-pixi/1.2.3`) |
| GitHub Release | One per tag; one asset: `devfeats-<feature-id>.tar.gz` |
| GHCR image | `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>` tagged `:latest`, `:<major>`, `:<major.minor>`, `:<major.minor.patch>` |

The shared library has its own separate identity: Git tag `lib/<X.Y.Z>` and one GitHub Release with the asset `devfeats-bashlib.tar.gz` (no GHCR image).

## Version-Bump Discipline (CI Guard)

Because `lib/` is embedded into every feature tarball as `lib/`, a `lib/` change semantically changes every feature's payload.

**Rule enforced on pull requests:** Any PR touching `lib/`, `features/install.sh`, or `features/<id>/` must bump the `version` field in the corresponding `metadata.yaml` files. For `lib/` and `features/install.sh` changes, all features must be bumped.

The guard runs as part of the `init` job in `main.yaml`. A failed check lists the features that need a version bump.

## Devcontainer Image

The CI devcontainer image (multi-arch: amd64/arm64) is built by `build-devcontainer.yaml` and published to GHCR. It is used as the execution environment for lint, validate, and devcontainer-mode feature tests.

The `init` job determines whether to rebuild the image or reuse the last published tag based on changes to `.devcontainer/.dev/`.

## Local Preview of Release Decisions

Before pushing, preview what the deployment pipeline will do:

```bash
just release-detect            # list features with untagged versions (queries GitHub API)
```

## References

- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/action — GitHub Action for publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
- [Dev Containers — Feature versioning](https://containers.dev/implementors/features/#versioning)
