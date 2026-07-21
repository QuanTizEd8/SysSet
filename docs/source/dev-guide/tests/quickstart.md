# Tests Quickstart

## Directory Layout

```
test/
├── environments.yaml            ← Central Docker image registry for all tests
├── environments.schema.json
├── features/
│   ├── generation.yaml          ← Global test-generation config
│   ├── defaults.shared.yaml     ← Options merged into every generated scenario
│   ├── {scenarios,checks,generation}.schema.json
│   └── <feature-id>/            ← ONLY when a feature overrides/augments generated tests
│       ├── scenarios.yaml       ← Extra/override scenarios + generation: block — edit this
│       └── checks.yaml          ← Extra/override assertions — edit this
│                                  (test scripts are rendered on the fly — no tests/*.sh on disk)
├── lib/
│   ├── *.bats                   ← BATS unit tests (one file per lib module)
│   ├── integration/             ← real-tool integration tier
│   ├── scenarios.yaml           ← BATS test environment matrix
│   ├── helpers/                 ← reload_lib(), stubs, JSON/ctx assertions
│   ├── setup_suite.bash         ← bash ≥4 guard (auto-discovered by bats)
│   └── bats/                    ← Git submodules (bats-core/-support/-assert/-file) — NEVER EDIT
├── install/
│   ├── *.bats                   ← install-framework unit tests (see {doc}`install`)
│   ├── scenarios.yaml           ← container matrix for install-framework CI
│   └── helpers/                 ← ensure_framework / source_framework + stubs / capture
└── proman/
    └── test_*.py                ← pytest tests for the build system (proman)
```


## When to Add Which Test

| Change | What to write |
|--------|--------------|
| New or changed `lib/` function | `@test` block in `test/lib/<module>.bats` |
| New or changed install framework helper in `install.tmpl.bash` | `@test` in `test/install/<concern>.bats` — see {doc}`install` |
| New feature behavior not auto-derivable | New scenario in `scenarios.yaml` + checks in `checks.yaml` |
| Adjust an auto-generated scenario | A `generation:` block (`suppress` / `augment_tests`) in `scenarios.yaml` — see {doc}`features` |
| Feature install should fail (non-zero exit) | `kind: install_failure` check in `checks.yaml` |
| Feature behavior requiring real macOS | Scenario with `envs: [macos-current]` (or `macos-current+brew`) and `modes: [macos]` |
| Network-isolated code path | Standalone scenario with `standalone.network: none` |
| Non-root install path | Scenario with `setup: useradd -m -s /bin/bash <user>` and `devcontainer.remoteUser`/`standalone.user` |
| Build system / metadata change | `test/proman/test_*.py` |

## Running Tests

```bash
# Library tests (requires Docker)
just test-lib                         # lean tier in ubuntu-stable
just test-lib ubuntu-stable --module <module>  # e.g. --module ospkg
just test-lib-all ubuntu-stable       # ordinary both tiers in one platform
just test-lib-bootstrap ubuntu-stable # dedicated fresh bare profile
just test-lib-complete ubuntu-stable  # ordinary all then bootstrap
just test-lib-envs                    # lean tier in seven environments
just test-lib-integration-envs        # integration tier in seven environments
just test-lib-all-envs                # both tiers in seven environments
just test-lib-bootstrap-envs          # bootstrap in seven bare profiles
just test-lib-complete-envs           # seven jobs / 14 fresh containers in CI

# Install framework tests (requires synced src/)
just test-install
just test-install-mod <module>        # e.g. just test-install-mod dep_install
just test-install-env <env>           # e.g. just test-install-env ubuntu-stable

# Feature scenario tests (requires Docker)
just test-feats <feature>             # all modes for one feature
just test-feats <feature> --filter <scenario>  # single scenario
just test-feats-macos <feature>       # macOS-only scenarios (requires macOS runner)

# Build system tests (no Docker)
just test-py

# All local tests (lib + Python); optionally also a feature
just test [<feature>]
```

## Workflow for a New Feature

Most features need **no** hand-written tests — the generator derives them from `metadata.yaml`. Preview what it produces, then add overrides only if needed:

```bash
# 1. See the generated tests (no writes)
proman-test-gen-preview <feature>

# 2. (Optional) add overrides in test/features/<feature>/{scenarios,checks}.yaml,
#    using a generation: block to suppress/augment generated scenarios.

# 3. Validate and run
just validate-tests <feature>
just test-feats <feature>
```

Test scripts are rendered on-the-fly from `checks.yaml` — no sync step needed.
