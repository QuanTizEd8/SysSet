## CI

Three workflow files form the pipeline:

- **`cicd.yaml`** — Orchestrator. Defines all event triggers (push, tag, PR, manual). Runs a `detect` job that computes changed-file flags, then calls `ci.yaml` (reusable CI) and conditionally `cd.yaml` (reusable CD) for releases.
- **`ci.yaml`** — Reusable CI. All lint, validation, unit, feature, and dist test jobs. Also callable standalone via `workflow_dispatch`.
- **`cd.yaml`** — Reusable CD. Publishes features to GHCR and creates a GitHub Release. Callable standalone via `workflow_dispatch` with a `tag` input.

`detect` in `cicd.yaml` maps changed paths to specific jobs:

| Changed path | Jobs triggered |
|---|---|
| `*.sh`, `*.bash`, `*.bats` | `lint` |
| `src/**/devcontainer-feature.json` | `validate` |
| `lib/**`, `test/unit/**` | `unit-native`, `unit-linux` |
| `src/<f>/` or `test/<f>/` | `test-features` (matrix), `test-macos` if macOS scenarios exist |
| `install-os-pkg` in changed list | `test-os-pkg` (6-distro matrix) |
| `get.sh`, `sysset.sh`, `build-artifacts.sh`, `src/**`, `lib/**`, `test/dist/**` | `test-dist-*` |

On `workflow_dispatch` or `v*` tag push, all jobs run. CD runs only when `is_release=true` AND CI passes.

