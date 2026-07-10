# Development Workflow

## Task Runner

All routine tasks are implemented as `just` recipes in the `justfile`. Run:

```bash
just --list          # full list with descriptions, grouped by category
```

Tasks follow the naming convention `<type>-<domain>[-<modifier>]` (e.g. `format-sh`, `lint-py-check`, `test-feats`). The bare name applies changes; the `-check` suffix is the verify-only, no-write variant. See {doc}`/dev-guide/devops/dev` for the full architecture.

Every recipe routes to either a `pixi run <task>` call (Python-managed tools such as `proman`, `ruff`, `pytest`, and Sphinx) or a `bash .dev/scripts/...` call (system-level operations like Docker, BATS, and GHA log streaming). Most recipes delegate directly with no inline logic; a few composite recipes (`lint`, `test`, `work`) assemble a list of steps for the capture runner.

### Git Hooks

[Lefthook](https://github.com/evilmartians/lefthook) manages optional pre-commit hooks, defined in `.config/lefthook.yml`. Run `lefthook install` once after cloning to register the hooks. The pre-commit hook runs `just format-sh` on staged shell files and `just lint-py` plus `just format-py` on staged Python files (re-staging any fixes). Hooks are opt-in; CI enforces the same checks unconditionally.

## Typical Daily Loop

After making changes, the fastest path is **`just work`**, which formats, lints, re-syncs `src/`, and runs the tests impacted by your changed files — all in one command:

```bash
just work                      # format + lint + sync-src + targeted tests for changed files
```

To run individual steps:

```bash
# After editing features/ or lib/:
just sync-src                  # regenerate src/ from sources

# Format and lint:
just format                    # format all shell + Python files in place
just lint                      # check-only lint — what CI runs

# Run tests:
just test-lib                  # library unit tests in a container (requires Docker)
just test-feats <feature>      # feature scenario tests (requires Docker)

# Build and preview docs:
just build-docs-live           # live-reload docs in browser
```

Recipes that wrap their work in the capture runner (e.g. `lint`, `test-*`, `work`, `build-docs-live`) write a timestamped log under `.local/reports/<name>/` and print its path as the last line of output. CI-log fetches from `just fetch-gha` land under `.local/logs/gha/` instead.

## Code Style

### Shell

All shell scripts are formatted with **shfmt** and linted with **shellcheck**. Style is fully defined in `.editorconfig` (shfmt reads it automatically) and `.shellcheckrc`. Run `just format` to format and `just lint` to check.

`features/*/install.bash` are body-only files (no shebang). Shellcheck runs on the assembled `src/*/install.bash`, so run `just sync-src` before `just lint-sh-check` when `src/` is missing or stale.

In addition to shellcheck, `just lint` runs a project-specific check, `lint-sh-local-vars`, that requires function-scoped variables in `lib/*.{bash,sh}` to be declared `local` (module globals must be `ALL_CAPS` or `_<MODULE>__`-prefixed; suppressions live in `.config/lib-local-vars.allowlist`).

### Python

Python source under `.dev/lib/proman/` and `test/proman/` is formatted and linted with **ruff** (config in `.config/ruff.toml`). Run `just format-py` and `just lint-py`.

### Logging in Shell Scripts

Use `lib/logging.bash` functions — never bare `echo ... >&2`:

```bash
logging__info "Message"           # ℹ️  tier info (per-sink threshold)
logging__success "Done"           # ✅  tier info
logging__warn "Warning"           # ⚠️  tier warn
logging__error "Error"            # ⛔  tier error
logging__debug "Detail"           # 🐞  tier debug
logging__fatal "Critical"         # ❌  always console; always file when LOG_FILE set

# Domain-specific helpers (same tier as logging__info):
logging__install "Installing"     # 📦
logging__download "Fetching"      # 📥
logging__build "Compiling"        # 🔨
logging__detect "Detecting"       # 🛠️
```

`LOG_LEVEL` gates the console; `LOG_FILE` + `LOG_FILE_LEVEL` gate an append-only session log at exit. A helper runs if **either** sink wants its tier (e.g. quiet console + verbose file). Subprocess stdout/stderr are captured at the **debug** tier; `trace` enables `set -x` per sink. Call `logging__set_level` after parsing options, then `logging__setup` once levels are final. Installer exit runs `logging__cleanup` then `file__session_cleanup` (scratch under `_FILE__SESSION_ROOT`). See `lib/logging.bash`, `lib/file.bash`, and {doc}`/user-guide/options` (Logging).
