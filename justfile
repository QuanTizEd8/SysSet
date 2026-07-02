# DevFeats Developer Tasks.
#
# List recipes: `just --list`.
# Global: bash, strict mode.
#
# ── Invocation patterns ───────────────────────────────────────────────────────
#
#   pixi run [--environment ENV] <task>   all pixi-managed tools (proman, ruff, sphinx)
#   bash .dev/scripts/CATEGORY/SCRIPT.sh  system-level ops (Docker, bats, streaming)
#
# ── Naming convention ─────────────────────────────────────────────────────────
#
#   <type>-<domain>[-<modifier>]
#
#   Types:   sync · build · lint · format · test · fetch · show · release · run
#   Domains: sh · py · src · feats · lib · docs · gha
#   Modifiers: check (verify-only) · live (file-watch) · pkg · env · envs · mod · macos
#
#   Bare name = apply/write; -check variant = verify-only (no writes).
#   Composite tasks (no domain) run every subdomain variant: lint, format, test.

set shell := ["bash", "-euo", "pipefail", "-c"]
# Required for recipe bodies that forward variadic params via "$@" (e.g.
# lint-sh-check, lint-sh-local-vars) — without this, just never populates
# $@/$#/$1... for non-shebang recipes, so "$@" is always empty and such
# recipes silently fall back to their no-args (scan-everything) behavior.
set positional-arguments := true


# ── Format ────────────────────────────────────────────────────────────────────

[
  group('format'),
  doc('Format all files: shell + Python.')
]
format: format-sh format-py


[
  group('format'),
  doc('Check formatting of all files without writing.')
]
format-check: format-sh-check format-py-check


[
  group('format'),
  doc('Format shell files with shfmt; pass paths to limit scope.')
]
format-sh *files:
    bash .dev/scripts/format/shfmt.sh {{files}}


[
  group('format'),
  doc('Check shell file formatting with shfmt without writing (CI-only); pass paths to limit scope.')
]
format-sh-check *files:
    bash .dev/scripts/format/shfmt.sh --check {{files}}


[
  group('format'),
  doc('Format Python files with ruff; pass paths to limit scope.')
]
format-py *files:
    pixi run --environment lint format-py {{ if files != "" { "-- " + files } else { "" } }}


[
  group('format'),
  doc('Check Python formatting with ruff (CI-style, no writes).')
]
format-py-check:
    pixi run --environment lint format-py-check


# ── Lint ──────────────────────────────────────────────────────────────────────

[
  group('lint'),
  doc('Run all linters: shell + Python (check only, no writes).')
]
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    exec bash .dev/scripts/capture/composite.sh lint -- \
      lint-sh-check -- bash .dev/scripts/lint/sh-check.sh \
      lint-sh-local-vars -- bash .dev/scripts/lint/sh-local-vars.sh \
      lint-py-check -- pixi run --environment lint lint-py-check


[
  group('lint'),
  doc('Lint and fix Python files with ruff.')
]
lint-py *files:
    just capture lint-py -- pixi run --environment lint lint-py {{ if files != "" { "-- " + files } else { "" } }}


[
  group('lint'),
  doc('Shellcheck tracked shell and assembled src/*/install.bash; pass paths to limit scope.')
]
lint-sh-check *files:
    just capture lint-sh-check -- bash .dev/scripts/lint/sh-check.sh "$@"


[
  group('lint'),
  doc('Require local declarations for function-scoped variables in lib/*.{bash,sh}.')
]
lint-sh-local-vars *files:
    just capture lint-sh-local-vars -- bash .dev/scripts/lint/sh-local-vars.sh "$@"


[
  group('lint'),
  doc('Check Python files with ruff (no fixes).')
]
lint-py-check:
    just capture lint-py-check -- pixi run --environment lint lint-py-check


# ── Work ──────────────────────────────────────────────────────────────────────

[
  doc('Format, lint, sync-src, and test for changed files; per-step reports under .local/reports/work/.')
]
work:
    bash .dev/scripts/work/work.sh


# ── Sync ──────────────────────────────────────────────────────────────────────

[
  group('sync'),
  doc('Run all sync tasks (sync-src).')
]
sync: sync-src


[
  group('sync'),
  doc('Regenerate git-ignored src/ from features/, lib/, bootstrap (JSON, deps, install.bash, _lib/, files/).')
]
sync-src:
    pixi run sync-src


[
  group('sync'),
  doc('Fail if src/ is stale or missing (no writes); same as proman-sync --check.')
]
sync-src-check:
    pixi run sync-src-check


[
  group('sync'),
  doc('Validate test/features/*/checks.yaml and scenarios.yaml against JSON Schema.')
]
validate-tests feat="":
    pixi run --environment test validate-tests {{ feat }}


# ── Build ─────────────────────────────────────────────────────────────────────

[
  group('build'),
  doc('Build dist/ release artifacts; pass args directly to proman-build-feats (e.g. just build-feats v1.2.3); runs sync-src first.')
]
build-feats *args: sync-src
    pixi run build-feats {{args}}


[
  group('build'),
  doc('Build dist/ library artifact (devfeats-bashlib.tar.gz) from lib/metadata.yaml and lib/.')
]
build-lib:
    pixi run build-lib


[
  group('build'),
  doc('Build Sphinx docs site to .local/build/docs/.')
]
build-docs:
    pixi run build-docs


[
  group('build'),
  doc('Live-rebuild Sphinx with browser preview.')
]
build-docs-live:
    just capture build-docs-live -- pixi run build-docs-live


[
  group('build'),
  doc('Package .local/build/docs/ into a GitHub Pages artifact tarball.')
]
build-docs-pkg: build-docs
    pixi run build-docs-pkg


# ── Test ──────────────────────────────────────────────────────────────────────

[
  group('test'),
  doc('Run lib/ unit tests in a container env (default: ubuntu-stable). Args forwarded to run-unit.sh e.g. just test-lib ubuntu-stable --module ospkg.')
]
test-lib env="ubuntu-stable" *args:
    just capture test-lib -- pixi run --environment test test-lib-env {{env}} {{args}}


[
  group('test'),
  doc('Run lib/ unit tests in all container environments (requires docker).')
]
test-lib-envs *args:
    just capture test-lib-envs -- pixi run --environment test test-lib-envs {{args}}


[
  group('test'),
  doc('Run install framework bats tests (requires synced src/ from just sync-src).')
]
test-install:
    just capture test-install -- bash .dev/scripts/test/run-install.sh


[
  group('test'),
  doc('Run install framework tests for one module e.g. just test-install-mod dep_install.')
]
test-install-mod module:
    just capture test-install-mod -- bash .dev/scripts/test/run-install.sh --module {{module}}


[
  group('test'),
  doc('Run install framework tests in one container e.g. just test-install-env ubuntu-stable.')
]
test-install-env env *args:
    just capture test-install-env -- pixi run --environment test test-install-env {{env}} {{args}}


[
  group('test'),
  doc('Run install framework tests in all container environments (requires docker).')
]
test-install-envs *args:
    just capture test-install-envs -- pixi run --environment test test-install-envs {{args}}


[
  group('test'),
  doc('Run Python unit tests for proman/ (pytest).')
]
test-py:
    just capture test-py -- pixi run --environment test test-py


[
  group('test'),
  doc('Run scenario and fail tests for one feature e.g. just test-feats install-pixi.')
]
test-feats feat *args:
    just capture test-feats -- pixi run --environment test test-feats {{feat}} {{args}}


[
  group('test'),
  doc('Run macOS scenarios for a feature natively e.g. just test-feats-macos install-pixi.')
]
test-feats-macos feat *args:
    just capture test-feats-macos -- pixi run --environment test test-feats {{feat}} --mode macos {{args}}


[
  group('test'),
  doc('Run local test suites: lib + Python; pass a feature id to also run test-feats. Requires docker for feature tests.')
]
test feat="":
    #!/usr/bin/env bash
    set -euo pipefail
    feat='{{feat}}'
    steps=(test-lib -- bash .dev/scripts/test/run-unit.sh)
    steps+=(test-py -- pixi run --environment test test-py)
    if [[ -n "$feat" ]]; then
      steps+=(test-feats -- pixi run --environment test test-feats "$feat")
    fi
    exec bash .dev/scripts/capture/composite.sh test -- "${steps[@]}"


# ── Release ───────────────────────────────────────────────────────────────────

[
  group('release'),
  doc('Preview which features need a new GitHub Release (queries GitHub API). Extra args pass through to proman-release-detect.')
]
release-detect *args:
    pixi run release-detect {{args}}


# ── Show ──────────────────────────────────────────────────────────────────────

[
  group('show'),
  doc('Print a list of all features and their descriptions.')
]
show-feats:
    pixi run show-feats


[
  group('show'),
  doc('Print a list of all feature options and their number of occurrences across all features.')
]
show-feat-opts:
    pixi run show-feat-opts


[
  group('show'),
  doc('Print one value from .config/proman/<file>.yaml (yq path). Example: just show-config ci image.suffix')
]
show-config file key:
    bash .dev/scripts/show/config.sh {{file}} {{key}}


# ── Fetch ─────────────────────────────────────────────────────────────────────

[
  group('fetch'),
  doc('Fetch GHA workflow run logs; pass args through directly (e.g. just fetch-gha --run <id> or just fetch-gha --commit <sha>). Logs in .local/logs/gha/; failed feature-test jobs also get <job-id>.trace.log (feat-log artifact).')
]
fetch-gha *args:
    bash .dev/scripts/fetch/gha.sh {{args}}


# ── Internal ──────────────────────────────────────────────────────────────────

[
  private,
  doc('Run a command with live output and a timestamped log under .local/reports/<name>/.')
]
capture name +command:
    bash .dev/scripts/capture/single.sh {{name}} -- {{command}}

[
  private,
  doc('Run any command inside a Docker-in-Docker environment (GHA CI use only).')
]
run-gha-dind *args:
    bash .dev/scripts/ci/gha-dind.sh {{args}}
