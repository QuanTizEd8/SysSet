# Build System Tests

The Python build system (`proman`) has its own pytest test suite under `test/proman/`.

## Running

```bash
just test-py                  # run all proman tests
```

Tests run in the `test` pixi environment (activated automatically via `pixi run --environment test`).

## What's Covered

`test/proman/` holds ~40 `test_*.py` files (browse the directory for the full, current set). They cluster into a few areas:

| Area | Example files | What it tests |
|------|---------------|---------------|
| Metadata & config | `test_metadata.py`, `test_config*.py` | `metadata.yaml` parsing/validation; project-config loading |
| Sync / codegen | `test_codegen.py`, `test_install_script_codegen.py` | `install.bash` and `devcontainer-feature.json` generation |
| Schemas | `test_argparse_manifest_schema.py`, `test_schema_bundle.py` | schema validation and docs-schema bundling |
| Test-generation engine | `test_gen_*.py` (≈15 files) | the feature-test generator: rules, outcome model, method resolver, env selection, blocks |
| Test loading / validation | `test_feature_test_loader.py`, `test_effective_suppress.py`, `test_scenarios.py`, `test_checks.py`, `test_environments.py` | merging generated + hand-written tests, suppression, schema validation |
| CI / release | `test_cicd_detect.py`, `test_detect_releasable.py` | change detection and release eligibility |

`test/proman/` itself is the source of truth — this table is an orientation aid, not an exhaustive list.

## When to Add Tests

Add or update `test/proman/` tests when:

- Changing feature metadata parsing logic in `.dev/lib/proman/metadata.py`
- Changing code generation in `.dev/lib/proman/sync/install_script.py`
- Changing config loading in `.dev/lib/proman/config.py`
- Adding a new proman CLI command
- Changing schema validation or bundling logic
- Changing the test generation pipeline

## Running in CI

Python tests run in the `test-dev` workflow (`.github/workflows/test-dev.yaml`), triggered by changes to `.dev/lib/**`, `.config/proman/**`, or `test/proman/**`.
