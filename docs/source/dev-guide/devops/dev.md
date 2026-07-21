# Development Infrastructure

## Task Architecture

Development tasks are split across four tiers with strict ownership rules. Each tier has exactly one job; the goal is that any new task has an obvious home.

| Tier | Tool | Rule |
|------|------|------|
| **Entry point** | `justfile` | Every developer command lives here. Zero inline logic — pure routing to a pixi task or a bash script. |
| **Python logic** | `proman` (`.dev/lib/`) | Anything that reads project metadata, feature manifests, or YAML config; multi-step orchestration; GitHub API calls. |
| **System ops** | `.dev/scripts/` | Docker socket management, bats orchestration, GHA log streaming. Operations that must run outside a managed Python environment. |
| **Environments** | `pixi.toml` | Python environment definitions plus tasks that use pixi-native features (`depends-on`, `cwd`, non-default environments). |

### Where does a new task go?

```
Does it read feature metadata, YAML config, or call an external API?
  → proman (new CLI entry point in .dev/lib/proman/cli/)

Does it require a specific Python environment, or use pixi's depends-on / cwd?
  → pixi task (add to the relevant [feature.X.tasks] block in pixi.toml)

Is it Docker/process management, bats, or a streaming shell operation?
  → .dev/scripts/CATEGORY/script.sh

Otherwise (justfile alias for any of the above)?
  → justfile recipe (routes to one of the three above)
```

---

## Invocation Patterns

Every `justfile` recipe uses exactly one of two patterns:

```bash
# Pattern 1 — pixi-managed tools (proman, ruff, sphinx, pytest)
pixi run [--environment ENV] <task-name>

# Pattern 2 — system-level bash ops (Docker, bats, streaming)
bash .dev/scripts/CATEGORY/SCRIPT.sh [args]
```

Proman entry points are **never** called directly from the justfile — always via `pixi run <task>`. This ensures the correct environment is activated and the binary is on PATH regardless of the shell context.

---

## Naming Convention

All task names follow `<type>-<domain>[-<modifier>]`.

### Types

| Type | Meaning |
|------|---------|
| `sync` | Assemble or reconcile derived files from sources |
| `build` | Produce a distributable artifact |
| `lint` | Static analysis |
| `format` | Reformat code |
| `test` | Run a test suite |
| `fetch` | Retrieve data from an external service |
| `show` | Print a human-readable inventory |
| `release` | Release lifecycle operations |
| `run` | One-shot internal execution wrapper (private tasks only) |

### Domains

| Domain | Covers |
|--------|--------|
| `sh` | Shell/bash files (`.sh`, `.bash`, `.bats`) |
| `py` | Python source (`proman/`) |
| `src` | Assembled `src/` tree |
| `feats` | Individual features (`features/`, `dist/`) |
| `tests` | Generated test scripts (`test/features/*/tests/`) |
| `lib` | `lib/` shell library |
| `docs` | Documentation (`docs/`, Sphinx, injected markers) |
| `gha` | GitHub Actions CI tooling |

### Modifiers

| Modifier | Meaning |
|----------|---------|
| `check` | Dry-run / verify-only (no writes, exits non-zero if changes needed) |
| `live` | Long-running with file-watching |
| `pkg` | Package/archive for distribution |
| `env` | Single-environment variant |
| `envs` | All-environments variant |
| `mod` | Single-module variant |
| `macos` | macOS-specific variant |

**`check` rule:** The bare name applies changes (`sync-src`, `format-sh`, `lint-py`). The `-check` suffix is always the verify-only variant (`sync-src-check`, `format-sh-check`, `lint-py-check`). Uniform across all types.

**`lint` specifics:** For tools that support auto-fix (ruff), the bare name applies fixes. For check-only tools (shellcheck), only the `-check` variant exists.

**Composites (no domain):** Only tasks that run every subdomain variant: `lint`, `format`, `format-check`, `test`.

---

## Task Reference

Run `just --list` for the current authoritative task list with descriptions. The table below maps each recipe to its implementation:

| justfile recipe | pixi task | Implementation |
|-----------------|-----------|----------------|
| `sync-src` | `sync-src` | `proman-sync` |
| `sync-src-check` | `sync-src-check` | `proman-sync --check` |
| `build-feats` | `build-feats` | `proman-build-feats` |
| `build-docs` | `build-docs` | Sphinx + `proman-gen-docs-data` |
| `build-docs-live` | `build-docs-live` | `sphinx-autobuild` |
| `build-docs-pkg` | `build-docs-pkg` | `proman-build-docs-pkg` |
| `release-detect` | `release-detect` | `proman-release-detect` |
| `show-feats` | `show-feats` | `proman-show-feats` |
| `show-feat-opts` | `show-feat-opts` | `proman-show-feat-opts` |
| `show-config` | — | `bash .dev/scripts/show/config.sh` |
| `lint-sh-check` | — | `bash .dev/scripts/lint/sh-check.sh` |
| `lint-py-check` | `lint-py-check` | `ruff check` |
| `lint-py` | `lint-py` | `ruff check --fix` |
| `format-sh` | — | `bash .dev/scripts/format/shfmt.sh` |
| `format-sh-check` | — | `bash .dev/scripts/format/shfmt.sh --check` |
| `format-py` | `format-py` | `ruff format` |
| `format-py-check` | `format-py-check` | `ruff format --check` |
| `test-lib`, `test-lib-integration`, `test-lib-all` | `test-lib-platform` | One platform's prepared ordinary profile at lean, integration, or all tier |
| `test-lib-bootstrap`, `test-lib-complete` | `test-lib-platform` | One platform's bare bootstrap profile, or ordinary all then bootstrap |
| `test-lib-envs`, `test-lib-integration-envs`, `test-lib-all-envs` | `test-lib-platforms` | Ordinary tier across seven logical platforms |
| `test-lib-bootstrap-envs`, `test-lib-complete-envs` | `test-lib-platforms` | Bootstrap or complete workload across seven logical platforms |
| `test-py` | `test-py` | `pytest test/proman` |
| `test-feats` | `test-feats` | `proman-test-run` |
| `test-feats-macos` | `test-feats` | `proman-test-run --mode macos` |
| `fetch-gha` | — | `bash .dev/scripts/fetch/gha.sh` |

### Sphinx docs build context

Sphinx loads `.local/data_transfer/docs_build_context.json` (repo owner/name, feature metadata, `lib/` summaries). That file is written by `proman-gen-docs-data` (`pixi run _sync-docs-data` in the default environment). The `build-docs` pixi task depends on `_sync-docs-data`; `build-docs-live` also runs it before each autobuild cycle. The path lives under `.local/`, which is gitignored.

HTML output and the packaged Pages tarball are written under **`.local/build/docs/`** (`website.tar` next to the site). That directory is gitignored with the rest of `.local/`.

JSON Schemas listed in **`.config/proman/docs.yaml`** under `json_schemas_publish` are rewritten with stable `$id` / `$ref` URLs and copied to **`.local/build/docs/schema/`** (for example **`/schema/manifest.json`** for the ospkg manifest schema). Add paths there when introducing new public schemas. In schemas under **`features/`**, use **`$ref` paths relative to `features/`** (e.g. **`install-os-pkg/manifest.schema.json`**) so editor YAML language servers can load referenced files; proman still registers the same targets by **`file://`** URI when validating.


---

## .dev/scripts/ Reference

| Script | Purpose | Called from |
|--------|---------|-------------|
| `capture/single.sh` | Run a command with live output + timestamped log under `.local/reports/` | `just capture` (used by almost every recipe) |
| `capture/composite.sh` | Run multiple commands, each captured separately | `just lint`, `just test` |
| `format/shfmt.sh` | Shell formatter wrapper (shfmt) | `just format-sh`, `just format-sh-check` |
| `lint/sh-check.sh` | ShellCheck wrapper | `just lint-sh-check` |
| `show/config.sh` | Print a field from `.config/proman/*.yaml` via yq | `just show-config` |
| `ci/gha-dind.sh` | Docker-in-Docker setup for GHA | `just run-gha-dind` |
| `fetch/gha.sh` | Poll GHA workflow runs; save job logs under `.local/logs/gha/`; for failed feature-test matrix jobs, also download `feat-log-*` artifacts as `<job-id>.trace.log` | `just fetch-gha` |
| `work/work.sh` | Format + lint + sync + test in one pass | `just work` |
| `test/run-unit.sh` | Execute bats unit tests for `lib/`; handles macOS bash ≥4 re-exec | `proman-test-lib-matrix` (via `just test-lib`) |
| `test/run-in-container.sh` | Docker exec wrapper (mounts repo, used by container matrix runs) | `proman-test-lib-matrix` |
| `git_helpers.sh` | Reusable git functions (sourced library) | Other scripts |

**Adding a new script:** Only add to `.dev/scripts/` if the operation is inherently bash — Docker/process management, bats orchestration, shell streaming. If it reads YAML config or makes decisions about project structure, it belongs in proman instead.
