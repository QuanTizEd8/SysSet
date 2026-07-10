# Generated `src/`

`src/` is fully auto-generated and **git-ignored**. Never edit files here — they are overwritten on every `just sync-src`.

## Layout

```
src/<feature-id>/
├── devcontainer-feature.json   ← Generated from metadata.yaml
├── install.sh                  ← Copied from features/install.sh (POSIX bootstrap)
├── install.bash                ← Rendered template with the feature body injected
├── lib/                        ← Copy of lib/ (modules + __init__.bash + .jq + schemas)
├── dependencies/               ← Resolved dependency manifests (sync artifact; not in the release tarball)
└── files/                      ← Copied from features/<feature-id>/files/ (if present)
```

## What Each File Does

**`devcontainer-feature.json`** — the OCI-compliant feature manifest consumed by the devcontainer CLI and published to GHCR. It is generated from `metadata.yaml` fields plus derived fields (id, documentationURL, licenseURL, OCI ref) injected from project config.

**`install.sh`** — the POSIX bootstrap. See {doc}`install.sh`.

**`install.bash`** — the assembled installer. The template from `features/install.tmpl.bash` provides the framework; the feature body from `features/<feature-id>/install.bash` is **injected after all template function definitions** (just before the final `__main__` dispatch call), then the whole file is formatted with `shfmt`. There is no "header + body" split — the entire template is rendered as one file. See {doc}`install.bash`.

**`lib/`** — a full copy of `lib/` (modules, `__init__.bash`, `.jq` filters, and schemas). Sourced at runtime via `lib/__init__.bash`. Each feature gets its own copy so that feature tarballs are self-contained.

## Sync Command

```bash
just sync-src           # regenerate src/ (run after any edit to features/ or lib/)
just sync-src-check     # verify src/ is current (exits non-zero if stale; used by CI)
```

`just sync-src` runs `proman-sync` (Python), which:
1. Loads and augments each `features/*/metadata.yaml` (merges `metadata.shared.yaml`, filters `_apply_when` options, runs the pyserials template filler) and validates it against `features/metadata.schema.json`.
2. Generates `devcontainer-feature.json` and renders `install.bash` for each feature.
3. Copies `features/install.sh`, all of `lib/`, and any other git-tracked feature-root asset (e.g. a `manifest.schema.json`) into each feature's output directory.
4. Copies any `features/<id>/files/` content.
5. Writes the `.devcontainer/{test,try}-<id>/devcontainer.json` live-testing containers (see {doc}`/dev-guide/tests/live`).

Feature discovery is automatic — any directory under `features/` that contains a `metadata.yaml` is treated as a feature.

## Why `src/` Is Ignored

- Files are exact copies or derivatives of source; committing them creates noisy diffs every time `lib/` is touched.
- CI regenerates `src/` at the start of every job to guarantee a clean, consistent working tree.
- The `.gitignore` makes it immediately obvious when someone accidentally edits a generated file (changes disappear on the next sync).
