# Feature Tests

Feature tests install a feature into a real container (or runner) and then assert the resulting system state. For most `install-*` features these tests are **auto-generated** from `metadata.yaml` — authors write little or nothing. When a feature needs cases the generator can't derive, authors add or override them under `test/features/<feature-id>/`.

## Files

A feature's `test/features/<feature-id>/` directory — present **only** when a feature augments or overrides the generated tests — holds two optional hand-authored YAML files:

| File | Edit? | Purpose |
|------|-------|---------|
| `scenarios.yaml` | ✅ Yes | Test matrix (environments, modes, options) plus a `generation:` block to suppress/augment generated scenarios |
| `checks.yaml` | ✅ Yes | Test assertions: the commands that verify a scenario passed |

The actual test shell scripts are rendered **on the fly** by the runner from `checks.yaml` (merged with generated checks) — there is no persisted `tests/*.sh` directory and no sync step.

## Test Generation & Overrides

A test-generation engine (`.dev/lib/proman/test/gen/`) derives a feature's scenarios and checks directly from its `metadata.yaml` (`_options`, `_dependencies`, `_system_requirements`). From the declared install methods, version pins, `if_exists` behavior, prefix/symlink settings, completions, and so on, it produces the mechanical matrix — method-per-package-manager installs, version-pinned/partial resolution, `if_exists` transitions, custom-prefix symlink/no-symlink cases, invalid-enum rejection, completions, and a log-file scenario — together with the checks that prove the resulting install state.

Because of this, **a fully-generated feature has no `test/features/<id>/` directory at all** (e.g. `install-node`); its tests exist only as generated content and still run under `just test-feats` and in CI.

Hand-written and generated tests are combined at a single merge point (`effective.load_effective`). The merge is **strict**: a hand-written scenario or check group whose name collides with a generated one is a hard error unless you explicitly suppress the generated one. To adjust generated tests, use the `generation:` block in `scenarios.yaml`:

```yaml
generation:
  suppress:
    scenarios: [package_default, source_default]   # drop these generated scenarios
    checks: [package_default]                       # drop these generated check groups
    check_items: ["symlink points to"]              # drop generated check items by title prefix
  augment_tests:
    default: [extra_smoke]                          # append hand-written check groups to a generated scenario
```

- **`suppress.scenarios` / `suppress.checks`** — remove named generated scenarios / check groups (e.g. to replace them with hand-written ones of the same name).
- **`suppress.check_items`** — remove individual generated check items (matched by title prefix), keeping the rest of the group.
- **`augment_tests`** — append hand-written `checks.yaml` group ids to a *generated* scenario's `tests:` list, so it stays generated but gains extra assertions.

Whether generation applies to a feature (plus its environment pool and per-family settings) is configured in **`test/features/generation.yaml`**. Preview and validate the result:

```bash
proman-test-gen-preview <feature>   # print the generated scenarios + checks (no writes)
just validate-tests [feature]       # validate merged (generated + hand-written) tests vs schema (CI runs this)
```

`test/features/install-rust/` and `test/features/install-jq/` are good real-world examples of overriding generated tests with documented rationale.

## Feature Tests vs Library Unit Tests

| Layer | Location | What it proves |
|-------|----------|----------------|
| Library unit tests | `test/lib/*.bats` | Functions in `lib/` in isolation (stubs, PATH fakes, `reload_lib`) |
| Feature scenario tests | `test/features/<id>/` | End-to-end `install.sh` / assembled `install.bash` behaviour in real containers |

**Do not put library-only logic in `test/features/`.** If a scenario never runs `install.sh` (or only sources `lib/*.bash` / `lib/*.sh` and calls helpers), it belongs in `test/lib/` — for example, HTTP URI resolution via a stubbed helper belongs in `test/lib/uri.bats`. Install-framework orchestration helpers belong in `test/install/` — see {doc}`/dev-guide/tests/install`.

Feature scenarios should either:
1. Let the runner call `install.sh` once with `options` from `scenarios.yaml` (default), then assert post-install state in the test script, or
2. Use `expect_install_failure: true` when the install must exit non-zero (see the `scenarios.yaml` format section below), or
3. Use `standalone.skip_install: true` only when the runner cannot perform the install you need (see below).

### When to use `skip_install`

Use `standalone.skip_install: true` only when the test script must invoke the installer under conditions the runner does not support:

- **Non-root install** — the standalone runner installs as root by default; use `standalone.user` for test assertions, then invoke `install.bash` explicitly in the test `pre` block as that user.
- **Custom CLI** — rare cases where options cannot be expressed via `scenarios.yaml` `options` (prefer exporting env vars instead).

Do **not** use `skip_install` to skip the feature install and only test `lib/` helpers — those belong in `test/lib/`.

## Shared defaults and logging

All feature scenarios inherit options from `test/features/defaults.shared.yaml` (lowest
precedence), then optional per-feature `defaults:` in `scenarios.yaml`, then scenario-level
`options:`:

| Option | Default | Role in tests |
|--------|---------|----------------|
| `log_level` | `debug` | Console verbosity during install |
| `log_file_level` | `debug` | File verbosity (bash xtrace only turns on at `trace`) |
| `log_file` | `/tmp/devfeats-feature.log` | In-container path for the install session log |

Dedicated `log_file` scenarios (e.g. `log_file` in `install-git`) override `log_file` with
a feature-specific path; assertions in `checks.yaml` still target that path inside the
container. The test runner always copies the install log to a canonical host file (see below).

`log_file_level: trace` enables bash `set -x` xtrace inside the install script, which is
useful for debugging but roughly an order of magnitude slower (measured: ~9x on a fast,
network-free scenario) — that's why it's off by default. To get xtrace back for one run,
pass `--log-level`/`--log-file-level`/`--xtrace` to `proman-test-run` (available via
`just test-feats <feature> --xtrace` and `just test-feats-macos <feature> --xtrace`); these
flags override `log_file`/`log_level` for every scenario in that run, taking precedence over
`scenarios.yaml` and the shared defaults. In CI, the same trace level is applied automatically
whenever the job is re-run with GitHub's "Enable debug logging" option — see
{doc}`/dev-guide/devops/ci`.

## Install log capture

`proman-test-run` (via `just test-feats`) writes one host log per test run under
`.local/logs/tests/features/<feature>--<scenario-key>--<mode>.log` (gitignored), where
`scenario-key` always includes the environment name (e.g. `default.ubuntu-stable`).
Layout is defined in `.config/proman/_main.yaml` (`path.local_logs_features`).

| Mode | How the log reaches the host |
|------|------------------------------|
| **standalone** | Bind-mount `.local/logs/tests/features` at `/log-out`; install copies `${LOG_FILE}` to `/log-out/<feature>--<key>--linux.log` before the container exits |
| **devcontainer** | Install runs at image build (before mounts). Runtime bind mount via `DEVFEATS_LOG_BIND_DIR` → `/log-out`; every generated test script copies the install log from its `log_file` path onto `/log-out/<feature>--<key>--devcontainer.log` before `reportResults` so CI can upload it |
| **macOS** | Install uses the scenario `log_file` (often under `/tmp/`); after the run, the file is copied to `.local/logs/tests/features/<feature>--<key>--macos.log` |

CI uploads each matrix log as `feat-log-<feature>-<scenario-key>-<mode>` (see
{doc}`/dev-guide/devops/ci`). When debugging CI locally, `just fetch-gha` saves GHA job
output as `<job-id>.log` and, for failed feature-test matrix jobs, the matching artifact as
`<job-id>.trace.log` beside it.

## `scenarios.yaml` Format

```yaml
# Optional per-feature defaults merged into every scenario (override shared defaults)
defaults:
  options:
    if_exists: skip

# Each top-level key is a scenario name
default_install:
  envs: [ubuntu-stable]          # Docker image keys from test/environments.yaml
  modes: [devcontainer]         # devcontainer | standalone | macos
  tests: [default_install]   # checks.yaml group IDs (scripts are tests/<id>.sh)

source_build:
  envs: [ubuntu-stable, alpine-current]
  modes: [devcontainer]
  options:
    method: source
    version: stable
  tests: [source_build]

gitconfig_user:
  envs: [ubuntu-stable]
  modes: [devcontainer]
  setup: useradd -m -s /bin/bash vscode   # shell commands run inside the container before install
  options:
    add_remote_user: true
    user_name: Dev User
  devcontainer:
    remoteUser: vscode   # mode-specific overrides
  tests: [gitconfig_user]

network_isolated:
  envs: [ubuntu-stable]
  modes: [standalone]
  standalone:
    network: none    # run with --network none
  tests: [network_isolated]

macos_default:
  envs: [macos-current+brew]   # references a macOS environment in test/environments.yaml
  modes: [macos]
  tests: [macos_default]

invalid_method:
  expect_install_failure: true   # assert the installer exits non-zero
  envs: [ubuntu-stable]
  modes: [devcontainer]
  options:
    method: invalid_value
  tests: [invalid_method]
```

Two top-level keys are reserved: **`defaults`** (a scenario body merged into every scenario) and **`generation`** (the suppress/augment directives from [Test Generation & Overrides](#test-generation-overrides)). Every other top-level key is a scenario name.

**Scenario-level keys:**

| Key | Description |
|-----|-------------|
| `envs` | Docker image keys from `test/environments.yaml` — see that file for the full list |
| `modes` | `devcontainer`, `standalone`, `macos` — defaults to `[devcontainer, standalone]` if omitted |
| `options` | Feature option key/value pairs; merged with `defaults.options` (scenario wins) |
| `tests` | `checks.yaml` group IDs (generated scripts live at `tests/<id>.sh`) |
| `setup` | Shell commands run inside the container before install. In standalone mode: executed before `install.sh`. In devcontainer mode: baked into the generated Dockerfile as a `RUN` layer |
| — | `setup:` runs before the repo is checked out (devcontainer) or in a bare base-image shell, so `lib/net.bash` isn't available. A POSIX `retry <cmd>` function (3 attempts, 5s delay) is auto-injected into every `setup:`/env-bootstrap shell context — wrap package-manager calls (`apt-get`/`dnf`/`pacman`/`apk`/`zypper`) in it, e.g. `retry apt-get update`. Plain `curl` already retries transient failures (including DNS blips) on its own via `--retry` — see the existing calls in `test/environments.yaml` for the flags to copy (`--retry 60 --retry-delay 5 --retry-connrefused`) |
| `expect_install_failure` | If `true`, asserts the installer exits non-zero; runner validates exit code and every `kind: install_failure` `pattern` in the scenario's checks |
| `devcontainer` | Mode-specific overrides: `remoteUser`, `containerUser` |
| `standalone` | Mode-specific overrides: `user` (run tests as this user), `sudo: false` (disable sudo for user), `network: none` (block outbound traffic), `skip_install: true` (test script calls install itself) |
| `fast_net_fail` | When `true`, set `DEVFEATS_NET_FETCH_RETRIES=1` and `DEVFEATS_NET_FETCH_DELAY=0` during install so expected unreachable-host failures finish quickly. Implied automatically when `standalone.network: none` |
| `args` | Extra CLI args passed to `install.sh` (rare; prefer `options` / `env_vars`) |
| `env_vars` | Extra environment variables set for the install |
| `test_shell` | `login` or `nonlogin` — shell style for generated standalone test scripts |

**`modes`:**
- `devcontainer` — installs via the devcontainer CLI in a Docker container.
- `standalone` — runs `install.bash` directly in a plain Docker container.
- `macos` — runs on a native macOS runner.

### Devcontainer mode artifacts

For `modes` that include `devcontainer`, `proman-test-run` generates a temporary project under `.local/` (gitignored) before calling the devcontainer CLI:

| Generated artifact | Source | Edit? |
|--------------------|--------|-------|
| `scenarios.json` | `scenarios.yaml` + `test/environments.yaml` | ❌ Never — regenerated on every `just test-feats` run |
| `<scenario>/Dockerfile` | `setup` commands and environment `build.dockerfile` layers | ❌ Never |
| `tests/*.sh` | `checks.yaml` | ❌ Never — rendered on-the-fly by the test runner |

Each `scenarios.json` entry is a complete `devcontainer.json` object (image/build, feature options, `remoteUser`, etc.). Hand-author **`scenarios.yaml` only** — the JSON is an implementation detail of the test runner.

## `checks.yaml` Format

```yaml
# Top-level key matches a scenario name in scenarios.yaml (or can be shared)
default_install:
  description: Default install on Ubuntu.    # optional comment in generated script
  pre: |                                      # optional: verbatim shell before checks
    export EXPECTED_VERSION="1.2.3"
  post: |                                     # optional: shell run on EXIT trap (cleanup)
    rm -f /tmp/test-artifact
  on_failure: |                               # optional: diagnostics when any check fails
    cat /var/log/installer.log
  checks:
    - title: tool on PATH                     # required: label shown in test output
      cmd: command -v tool                    # required: exits 0 to pass
    - title: version is at least 1.0
      cmd: bash -c '[ "$(tool --version | cut -d. -f1)" -ge 1 ]'
      debug: |                               # optional: unconditionally printed before this check
        echo "version output:"
        tool --version 2>&1 || true
      on_fail: |                             # optional: printed only when this check fails
        tool --version || echo "(failed)"
    - kind: fail                             # kind=fail: check passes when cmd exits non-zero
      title: tool rejects invalid input
      cmd: bash -c 'tool --invalid-flag 2>/dev/null'

invalid_method:
  description: Invalid method value causes installer to exit non-zero.
  checks:
    - kind: install_failure                  # asserts the install itself exits non-zero
      title: invalid method rejected
      pattern: "Invalid value for 'method'"  # required: substring that must appear in install output
```

**Check item fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `title` | ✅ | Label shown in test output |
| `cmd` | ✅ | Command to run |
| `kind` | | Assertion type: `check` (default, exits 0 passes), `fail` (exits non-zero passes), `multiple` (min N must pass), `install_failure` (asserts the install itself exits non-zero) |
| `pattern` | | When `kind: install_failure` — **required** substring that must appear in install stdout/stderr (proves the failure was for the expected reason) |
| `debug` | | Shell content printed unconditionally before this check (diagnostic output) |
| `on_fail` | | Shell content run only when this specific check fails |
| `min` | | When `kind: multiple` — minimum number of commands that must exit 0 |

### `kind: install_failure` and `expect_install_failure`

`kind: install_failure` in `checks.yaml` is a check item that asserts the install exits non-zero **and** that the install output contains every `pattern` substring declared on such checks in the scenario's test group. Each `install_failure` item must include a `pattern`. It is **not** emitted into the generated `.sh` file — the runner handles it directly. Any other `checks:` items in the same group that do not use `kind: install_failure` still run in the generated script (for example, verifying that a stub binary is still present after a failed install).

```yaml
# scenarios.yaml
invalid_method:
  expect_install_failure: true
  envs: [ubuntu-stable]
  modes: [devcontainer]
  options:
    method: invalid
  tests: [invalid_method]

# checks.yaml
invalid_method:
  checks:
    - kind: install_failure
      title: invalid method rejected
      pattern: "Invalid value for 'method'"
```

## Test Script Anatomy

Generated scripts (and any manually-written helper scripts for macOS or standalone) use `test/support/assert.sh`, which is API-compatible with `dev-container-features-test-lib`. The runner puts it on PATH before invoking the script:

```bash
#!/bin/bash
# One-line description of what this scenario verifies.
# AUTO-GENERATED from checks.yaml — DO NOT EDIT
set -e
. dev-container-features-test-lib

# --- basic checks ---
check "mytool is installed"       command -v mytool
check "version is correct"        bash -c "mytool --version | grep '1.2.3'"
check "config dir created"        test -d /root/.config/mytool

reportResults
```

`REPO_ROOT` is always set by the runner — use it to reference repo files from inside the container.

`reportResults` must always be the last statement; it exits non-zero if any check failed.

### Common Assertion Patterns

```bash
# Tool on PATH
check "mytool on PATH"              command -v mytool

# Version match (use grep -q or bash -c for compound checks)
check "version correct"             bash -c "mytool --version | grep -q '0.66'"

# File / directory existence
check "config dir exists"           test -d /root/.config/mytool
check "binary is executable"        test -x /usr/local/bin/mytool

# File content — use grep -Fq for literal strings, grep -q for patterns
check "PATH entry present"          grep -Fq 'export PATH' /root/.bashrc

# Value comparison (bash -c needed for arithmetic / subshell)
check "uid is 1000"                 bash -c '[ "$(id -u vscode)" = "1000" ]'

# Negative assertion — tool must NOT be present
check "tree not installed"          bash -c '! command -v tree'

# Passes when command exits non-zero (fail_check from assert.sh)
fail_check "invalid option fails"   mytool --unknown-flag
```

Use `bash -c '...'` whenever a check needs pipes, subshells, string comparison, or arithmetic. Use `grep -Fq` (fixed string) rather than `grep -q` (regex) for exact literal content checks.

`assert.sh` also provides `fail_check "label" <cmd>` (passes when the command exits non-zero) and `checkMultiple "label" <min> "cmd1" ["cmd2"...]` (passes when at least `<min>` commands exit 0).

## Test Script Generation

The test runner renders `test/features/<feature>/tests/<scenario>.sh` on-the-fly from `checks.yaml` — no disk copy is kept. The generated scripts use `dev-container-features-test-lib` (`check` / `reportResults` functions):

```bash
#!/bin/bash
# AUTO-GENERATED from checks.yaml — DO NOT EDIT
set -e
. dev-container-features-test-lib

check "tool on PATH" command -v tool
check "tool --version succeeds" tool --version
echo "=== debug output ==="
tool --version 2>&1 || echo "(failed)"

reportResults
```

## Running Feature Tests

```bash
# All modes for a feature
just test-feats install-git

# Filter to one scenario
just test-feats install-git --filter gitconfig_system

# Standalone mode only
just test-feats install-git --mode standalone

# macOS scenarios (must be run on macOS)
just test-feats-macos install-git
```

## Test Environments

`test/environments.yaml` is the central registry of all Docker images. Each key maps to a Docker image, optionally with a build step:

```yaml
ubuntu-stable:
  image: ubuntu:24.04

alpine-current+bash:
  image: alpine:3.24
  build:
    dockerfile: apk add --no-cache bash
```

Scenarios reference environment keys. The `+`-suffixed variants (e.g. `ubuntu-stable+bash+git`) are pre-built images with extra packages for tests that need those tools available before the feature installs anything.

The `build.dockerfile` value is inline shell commands. The test runner generates `FROM <image>\nRUN <<'EOF'\nset -eux\n<commands>\nEOF` and builds the image as `devfeats-env-<name>:latest`. For macOS environments (image key starts with `macos`), the commands run as native setup on the GHA runner before tests.

Custom environments with pre-condition state (e.g. an existing user, a stub tool, or a pre-installed package) belong in `test/environments.yaml`. Never duplicate inline Dockerfiles across multiple scenario files.

```yaml
# Example: environment with a pre-created non-root user + sudo
ubuntu-stable+vscode:
  image: ubuntu:24.04
  build:
    dockerfile: |
      apt-get update -qq
      apt-get install -y --no-install-recommends sudo
      useradd -m -s /bin/bash vscode
      echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Example: environment with a stub binary pre-installed
ubuntu-stable+tool-stub:
  image: ubuntu:24.04
  build:
    dockerfile: |
      printf '#!/bin/sh\necho "mytool 0.0.0-stub"\n' > /usr/local/bin/mytool
      chmod +x /usr/local/bin/mytool
```

`test/lib/scenarios.yaml` is a separate file for the BATS unit test matrix (a subset of the environments defined in `test/environments.yaml`).

## Options Key Transformation

In standalone and macOS modes, `scenarios.yaml` option keys are converted to environment variables before `install.bash` is called. The transformation is:
- `snake_case` → `SNAKE_CASE` (e.g. `log_level` → `LOG_LEVEL`)
- `kebab-case` → `KEBAB_CASE` without hyphens (e.g. `bin-dir` → `BIN_DIR`)
- `camelCase` → `CAMELCASE` (all caps, no separator)

In devcontainer mode, keys are passed as-is to the features config object.

## CI Integration

Feature tests run in the `test-features` reusable workflow (`.github/workflows/test-features.yaml`), triggered by the main pipeline when `features/<id>/` or `lib/` changes. Each matrix job runs a single scenario (`--filter <key>`) in DinD (Linux) or on a native macOS runner.

After each job, CI uploads `.local/logs/tests/features/<feature>--<scenario-key>--<mode>.log` as artifact
`feat-log-<feature>-<scenario-key>-<devcontainer|linux|macos>` (`if-no-files-found: ignore`).
Use these artifacts (or `just fetch-gha` trace sidecars) when GHA step logs are too terse.

See {doc}`/dev-guide/devops/ci` for the full CI setup and log-fetch workflow.

---

## Test Environment Reference

All named test environments are declared in `test/environments.yaml`, which is **authoritative** — the image pins below drift as distributions release new versions, so verify against the file. The canonical set of pinned base environments is roughly:

| Key | Docker image | Notes |
|---|---|---|
| `ubuntu-stable` | `ubuntu:24.04` | Ubuntu 24.04 LTS (Noble Numbat) — primary LTS baseline |
| `ubuntu-current` | `ubuntu:26.04` | Ubuntu 26.04 LTS — newer generation in matrix |
| `debian-stable` | `debian:12` | Debian 12 Bookworm — primary baseline |
| `debian-current` | `debian:13` | Debian 13 Trixie — newer generation in matrix |
| `alpine-current` | `alpine:3.24` | Alpine — version tracked in CI |
| `fedora-current` | `fedora:44` | Fedora — version tracked in CI |
| `rockylinux-current` | `rockylinux:10` | Rocky Linux — version tracked in CI |
| `opensuse-leap-current` | `opensuse/leap:16.0` | openSUSE Leap — version tracked in CI |
| `archlinux-current` | `archlinux:base-YYYYMMDD.0.XXXXXX` | Arch Linux — pinned dated immutable tag |
| `macos-current` | `macos-26` | macOS 26, bare (no Homebrew); `image` is GHA runner label |
| `macos-current+brew` | `macos-26` | macOS 26 with Homebrew |

**Never use rolling tags** (`ubuntu:latest`, `debian:latest`, etc.) — they silently change their contents and make CI non-reproducible.

### Naming convention

```
{family}-{track}[+{augmentation}...]  # track: stable | current (see header in environments.yaml)
{base}+{tool}                         # base + tool/shell/binary installed
{base}+{tool}-{version}               # base + specific version of tool
{base}+{tool1}+{tool2}                # base + multiple tools/toolchains
```

**Tracks:** `stable` and `current` are dual-track slots for Ubuntu and Debian only. All other families use a single `current` key for the version pinned in `image:` — bump the pin without renaming the key.

Where each `{tool}` segment names what is installed: a binary (`bash`, `git`, `go`, `brew`, `curl`), a version-pinned binary (`jq-1.8.1`, `gh-2.67.0`), or a build toolchain (`autotools`, `build-essential`, `ncurses`).

No categorical suffixes (`-preinstalled`, `-build-deps`, `-base`). The name should describe what's in the image, not why it was created.

**Which distros need a `+bash` variant:** Alpine, Rocky Linux, and openSUSE Leap do not ship bash by default. Their `+bash` variants (e.g. `alpine-current+bash`) are required for any test that uses the test shim or the devcontainer runner. Ubuntu, Debian, Fedora, and Arch Linux ship bash by default and do not need `+bash` variants. (`archlinux:base` includes bash via the base package group.)

**How to add a new environment:** add the entry to `test/environments.yaml` under the appropriate section header (base images → +bash → +shell → +tool[-version] → +toolchain → from:-chain → macOS). Verify it with `python3 -c "import yaml; yaml.safe_load(open('test/environments.yaml').read())"` before referencing it in a `scenarios.yaml`.

---

## Naming Conventions

The generator produces conforming names automatically (`naming.py`); these conventions apply to **hand-written** scenarios and checks and are enforced by CI validation (`just validate-tests`).

### Scenario keys

Scenario keys describe **what** option combination or behavior is being tested — not **where** (which OS, distro, or package manager). The `envs:` field captures "where."

**Forbidden in scenario keys:** OS names (`ubuntu`, `debian`, `alpine`, `fedora`, `rocky`, `opensuse`, `arch`), package manager names (`apt`, `apk`, `dnf`, `rpm`, `zypper`, `pacman`, `brew`).

**Exception:** `install-os-pkg` uses PM-prefixed scenario names intentionally (they describe the manifest section format being tested, which varies by PM).

Standard patterns:

| Pattern | When to use |
|---|---|
| `default` | Default options; no explicit method/version override |
| `package_default` | `method=package` across multiple distros |
| `source_default` | `method=source`, default prefix |
| `binary_pinned_version` | Explicit pinned version with binary method |
| `binary_custom_prefix` | Custom prefix with symlink discovery |
| `custom_prefix_no_symlink` | Custom prefix, `prefix_discovery=none` |
| `if_exists_skip` | `if_exists=skip` with pre-installed stub |
| `if_exists_fail` | `if_exists=fail` with pre-installed stub |
| `if_exists_reinstall` | `if_exists=reinstall` over pre-installed version |
| `completions_{shell}` | Shell completions for a specific shell |
| `method_npm` / `method_cargo` / etc. | Method-specific scenario (non-default method) |
| `upstream_package` / `upstream_package_default` | `method=upstream-package` |
| `macos_default` | macOS (always manual; no auto-generation) |

### Check titles

Check titles state the **expected post-install system state** declaratively. They must not contain package manager names (`dpkg`, `rpm`, `apk`, `dnf`, `brew`), OS names, or implementation details like "PPA."

Standard patterns:

| Pattern | Examples |
|---|---|
| `{tool} is on PATH` | `git is on PATH`, `rg is on PATH` |
| `{tool} binary is at {path}` | `git binary is at /usr/local/bin/git` |
| `{tool} binary is executable` | `git binary is executable` |
| `{tool} --version succeeds` | `git --version succeeds` |
| `{tool} version is {X.Y.Z}` | `jq version is 1.8.1` |
| `{tool} reports a version` | `rg reports a version` (format-only) |
| `binary is package-manager-managed` | replaces `is dpkg-managed`, `is rpm-managed` |
| `no upstream repo keyring` | replaces `PPA keyring cleaned up` |
| `no upstream repo sources entry` | replaces `PPA sources.list.d entry cleaned up` |
| `symlink exists at {path}` | `symlink exists at /usr/local/bin/rg` |
| `symlink points to {path}` | `symlink points to /opt/rg-bin/bin/rg` |
| `no file at {path}` | `no file at /usr/local/bin/rg` |

### Multi-platform scenarios

When the same option combination runs on multiple distros, use **one scenario** with multiple entries in `envs:`. The `expand_envs()` function creates one env-qualified run key per env (`scenario_name.env_name`, including when there is only one env).

```yaml
# Good: one scenario, multiple envs
package_default:
  envs: [alpine-current+bash, debian-stable, fedora-current, opensuse-leap-current+bash, archlinux-current]
  options: {method: package}
  tests: [package_default]

# Bad: three separate scenarios with identical options
package_alpine:
  envs: [alpine-current+bash]
  options: {method: package}
  tests: [package_alpine]

package_debian:
  envs: [debian-stable]
  options: {method: package}
  tests: [package_debian]
```

When a single multi-distro scenario needs to assert package-manager ownership, use `kind: multiple, min: 1` so the check passes regardless of which PM is in use:

```yaml
- title: binary is package-manager-managed
  kind: multiple
  min: 1
  cmd:
    - bash -c 'dpkg -S "$(command -v {tool})" >/dev/null 2>&1'
    - bash -c 'rpm -qf "$(command -v {tool})" >/dev/null 2>&1'
    - bash -c 'apk info -e {tool} >/dev/null 2>&1'
    - bash -c 'pacman -Qo "$(command -v {tool})" >/dev/null 2>&1'
```

Keep scenarios separate only when their `setup:` scripts must differ per distro (e.g., `install-homebrew` Linux distro scenarios each install zsh via a different PM). In that case, still avoid PM/OS names in the scenario key; use abstract names like `linux_rpm`, `linux_zypper`.
