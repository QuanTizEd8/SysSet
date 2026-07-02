# CI/CD Pipelines

The CI/CD stack lives under `.github/workflows/`. All workflows are reusable and called from a single orchestrator.

## Workflow Overview

| File | Type | Purpose |
|------|------|---------|
| `main.yaml` | Orchestrator | Detects what to run, calls all reusable workflows |
| `lint.yaml` | Reusable | Shell format-check + shellcheck, Python format-check + ruff, and devcontainer-feature.json schema validation |
| `test-lib.yaml` | Reusable | Library unit tests (BATS) in container matrix |
| `test-dev.yaml` | Reusable | Python unit tests for proman (pytest) |
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
| `lib/**` or `features/install.sh` | `test-features` for **all** features |
| `features/<id>/` or `test/features/<id>/` | `test-features` for **that feature only** |
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

### Feature Scenario Tests

Runs feature tests via `proman-test-run`. Three sub-modes run in parallel:

- **Devcontainer** (`test-features-devcontainer`): installs via the devcontainer CLI inside a Docker-in-Docker container running the CI devcontainer image. Each scenario matrix entry is an independent job.
- **Standalone Linux** (`test-features-linux`): runs `install.bash` directly in plain Docker containers (standalone mode).
- **macOS** (`test-features-macos`): runs on native `macos-latest` runners for scenarios with `modes: [macos]`.

Scenarios inherit logging defaults from `test/features/defaults.shared.yaml` (`log_level: debug`, `log_file_level: trace`). Each job uploads `.local/logs/tests/features/<feature>--<scenario-key>--<mode>.log` as a `feat-log-*` artifact for post-mortem analysis (see log table under **Monitoring CI** above).

### Docs Build

Builds the Sphinx site (`just build-docs`) and uploads the result as a GitHub Pages artifact.

### Build Features

Runs `just build-feats` to produce per-feature tarballs in `dist/`. These are uploaded as the `devfeats-dist` artifact and consumed by the deploy workflow.

## Deployment (`deploy.yaml`)

Deployment runs automatically on `push` to `main` when at least one feature has an untagged version. It requires CI to have passed.

### Deploy: GHCR

Uses `devcontainers/action` with `publish-features: "true"` to push each feature as an OCI image to GHCR. Tags: `:<major>`, `:<major.minor>`, `:<major.minor.patch>`.

Repo-tagging is disabled (`disable-repo-tagging: "true"`) — the `deploy-gh-release` job handles Git tags.

### Deploy: GitHub Releases

A matrix job runs per feature in `features_to_release`. For each feature:

1. Creates annotated Git tag `<feature-id>/<X.Y.Z>` on the commit.
2. Creates a GitHub Release `<feature-id>/<X.Y.Z>` with the feature tarball as the release asset (`devfeats-<feature-id>.tar.gz`).

### Deploy: Docs

Deploys the built docs site to GitHub Pages when docs content changes.

### Release Identity

Each feature has its own independent release identity:

| Artifact | Format |
|----------|--------|
| Git tag | `<feature-id>/<X.Y.Z>` (e.g. `install-pixi/1.2.3`) |
| GitHub Release | One per tag; one asset: `devfeats-<feature-id>.tar.gz` |
| GHCR image | `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>:<major>`, `:<major.minor>`, `:<major.minor.patch>` |

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
