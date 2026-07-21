# Library Unit Tests

Unit tests for `lib/` live under `test/lib/`. Each `.bats` file covers one module. Tests run without Docker by sourcing lib files directly into the bats test process. The ordinary suite runs on both Linux and macOS in CI.

## Vendor Libraries

BATS and its companion libraries are git submodules at `test/lib/bats/`. Initialise once after cloning:

```bash
git submodule update --init --recursive
```

Never edit files under `test/lib/bats/` — they are vendored.

| Submodule | Purpose |
|-----------|---------|
| `bats-core` | Test runner |
| `bats-support` | Failure output formatting |
| `bats-assert` | `assert_success`, `assert_output`, etc. |
| `bats-file` | `assert_file_exists`, `assert_dir_exists`, etc. |

## Test Tiers

Ordinary tests have two tiers:

- **Lean tier (default):** `test/lib/*.bats` only. In the Linux matrix it runs in the same prepared ordinary profile as integration tests; the tier name describes test selection, not a bash-only image contract. Run by `just test-lib` and `just test-lib-envs`.
- **Integration tier:** `test/lib/integration/*.bats`. Exercises real tools, package managers, and network services. Run by `just test-lib-integration` for one platform, `just test-lib-integration-envs` for all platforms, or natively with `bash .dev/scripts/test/run-unit.sh --tier integration`.

Use `--tier all` for the exact union of both tiers. Tier selection never recurses into the vendored BATS files under `test/lib/bats/`.

The matrix has seven logical Linux platforms (Ubuntu, Debian, Fedora, Rocky Linux, Alpine, openSUSE, and Arch). Each platform maps to two concrete profiles: a prepared **ordinary** image for lean/integration tests and a fresh bare **bootstrap** image for `test/lib/bootstrap/bootstrap.bats`. `complete` runs ordinary first and bootstrap second in separate containers; bootstrap still runs when ordinary fails. CI keeps seven Linux jobs, with two sequential fresh container executions per job (14 executions total).

Every ordinary image contains a pinned, checksum-verified bundle of jq 1.8.2, yq 4.53.2, Sourcemeta JSON Schema CLI 16.2.0, and ORAS 1.3.2 at `/opt/devfeats/lib-test-tools/bin`. It also contains the system prerequisites used by ordinary integration tests (including Git, GPG, archive tools, account-management utilities, and `flock` or `shlock` for BATS concurrency). The bundle is deliberately outside global `PATH`: the ordinary profile passes both `DEVFEATS_TEST_TOOL_CACHE=required` and the absolute `DEVFEATS_TEST_TOOL_SOURCE_DIR`; the suite exposes only its suite-scoped copies. The bootstrap profile passes only `DEVFEATS_TEST_TOOL_CACHE=disabled`, receives no source directory, and starts from the distinct bare image.

`--module <name>` filters the selected tier. Repeatable native-runner `--path <file>` instead selects exact, non-symlink `.bats` files directly under `test/lib/`, `test/lib/integration/`, or `test/lib/bootstrap/`; it cannot be combined with `--tier` or `--module`. Matrix mode rejects explicit paths so callers cannot cross profile boundaries. Use `--filter=<regex>` when a filter value begins with `--`. `--matrix-jobs` bounds concurrent logical platforms; the two profiles for a platform never overlap.

### Opt-in BATS Concurrency

BATS execution remains serial by default (`--jobs 1`) while full-suite stress testing and benchmarks are staged. An ordinary run may opt into 2 through 256 workers with `--jobs <n>`. The runner keeps test files in their canonical sequential order and parallelizes tests only within the active file. This preserves one TAP stream and prevents different modules' fixtures from overlapping.

Three integration modules remain serial within their file even when a larger job count is requested: npm shares a file-scoped installation prefix and log, ospkg mutates the real package database and coordinates package-manager processes, and users exercises an ordered lifecycle against the passwd/group databases. Bootstrap tests are runner-global serial and reject every `--jobs` value greater than 1.

Real-network integration modules opt into bounded test profiles: shared HTTP/ORAS calls use three attempts with short sleeps plus per-attempt connection and transfer timeouts, package-manager calls use two outer attempts, and npm uses its native bounded fetch settings. Production defaults are unchanged. The CI library jobs also have a 120-minute hard ceiling so a hung third-party client cannot consume the runner indefinitely.

Within-file concurrency requires either `flock` or `shlock` on `PATH`. Prepared environments install and verify a provider automatically. For an unprepared native environment, install util-linux on Linux or run `brew install flock` on macOS; otherwise use `--jobs 1`. A selection-only `--list-files` call does not require a lock provider.

Treat matrix and BATS concurrency as multiplicative: up to `--matrix-jobs M` environments, each using `--jobs N`, can demand roughly `M × N` concurrent test workers in addition to container and service overhead. Choose both limits for the host's CPU, memory, network, and package-manager capacity.

Install framework tests live separately under `test/install/` — see {doc}`install`.

## File Anatomy

```bash
# Load BATS companion libraries first.
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# Load project helpers.
load helpers/common   # provides reload_lib()
load helpers/stubs    # provides create_fake_bin(), begin/end_path_isolation()

# Reload the module under test before each test for a clean state.
setup() {
  reload_lib os.bash
}

@test "os__kernel returns the uname output" {
  uname() { printf 'Linux\n'; }
  export -f uname
  run os__kernel
  assert_success
  assert_output "Linux"
}
```

## `reload_lib`

**`reload_lib [<module.{bash,sh}>]`** — defined in `helpers/common.bash`. Call it in `setup()` to give every test a clean module state. The optional argument is accepted for readability and backward compatibility; the helper resets globals but does not re-source modules one by one. It:

1. Resets cached globals (`_OS__KERNEL`, `_NET__FETCH_TOOL`, `_OSPKG__DETECTED`, etc.).
2. Reinitializes shared test state such as `_CTX__REGISTRY`, `_OCI__AUTH_*`, and the pending logging journal.
3. Leaves module sourcing to `helpers/common.bash`, which loads `lib/__init__.bash` once per bats process at startup.

```bash
setup() {
  reload_lib ospkg.bash   # works for any module
}
```

To test load-guard idempotency, call `reload_lib` in `setup()` then source the file directly inside the test — the guard prevents re-sourcing.

### Why Modules Are Loaded Via `__init__.bash`

`ospkg.bash` contains `declare -A _OSPKG_OS_RELEASE=()`. When a file is sourced from **within a bash function**, `declare` without `-g` creates a **local** variable that disappears when the function returns. To avoid that trap for `ospkg.bash` and similar modules, `helpers/common.bash` sources `lib/__init__.bash` once at process startup instead of re-sourcing individual modules inside `reload_lib`.

Always use `reload_lib` rather than sourcing `ospkg.bash` directly in test setup unless the test is explicitly about load order or idempotency.

## Stubbing Commands

`helpers/stubs.bash` provides three helpers:

**`create_fake_bin <name> [stdout]`** + **`prepend_fake_bin_path`** — create a stub under `$BATS_TEST_TMPDIR/bin/` and prepend it to PATH:

```bash
create_fake_bin "curl" "fake-response"
create_fake_bin "apt-get" ""
prepend_fake_bin_path
```

Stubs are scoped to `$BATS_TEST_TMPDIR` (cleaned up by bats after each test).

**`begin_path_isolation [cmd...]`** / **`end_path_isolation`** — swap PATH to `$BATS_TEST_TMPDIR/bin` and optionally allow through explicit commands. Use when you need to prove a tool is absent even when the host/runner has it installed:

```bash
begin_path_isolation "mkdir" "cat" "bash"
run _json__ensure_jq
end_path_isolation
```

Prefer this over ad-hoc PATH save/restore to keep tests deterministic across machines.

## Overriding Commands with Shell Functions

```bash
uname() { printf 'Darwin\n'; }
export -f uname   # required: makes the override visible inside sourced lib files
```

`export -f` is essential — without it, the library's call to `uname` resolves to the real binary.

## Mocking Library Functions

```bash
@test "github__latest_tag parses tag_name from JSON" {
  reload_lib net.bash
  reload_lib github.bash
  github__fetch_release_json() {
    printf '{"tag_name":"v1.2.3"}\n'
    return 0
  }
  export -f github__fetch_release_json
  run github__latest_tag "owner/repo"
  assert_success
  assert_output "v1.2.3"
}
```

## Subprocess Isolation for `logging.sh`

`logging__setup` runs `exec 3>&1 4>&2` and redirects installer stdout into a FIFO mux. Bats uses fd 3 for TAP output — running setup in the test process corrupts reporting.

**Rule:** Every test calling `logging__setup` or `logging__cleanup` must run in a `bash -c` subprocess.

After setup, plain `echo` goes to the mux (not bats stdout). Use `echo … >&3` for assertions **before** `logging__cleanup`, or plain `echo` **after** cleanup when fds 1/2 are restored. Set `LOG_FILE` (and `LOG_FILE_LEVEL` if needed) **before** `logging__setup` so the journal captures live output. To assert console lines while setup is active, `exec 2>'${_stderr}'` at the start of the subprocess so saved fd 4 points at your capture file. Do not use bats `4>file` on `run` — setup's `exec 4>&2` overwrites that redirect.

```bash
@test "logging__setup creates a temp log file" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/logging.bash'
    logging__setup
    [[ -f \"\${_LOGGING__LOG_FILE_TMP}\" ]] && echo OK >&3
    logging__cleanup
  "
  assert_success
  assert_output "OK"
}
```

Dual-threshold tests should set `LOG_FILE` before setup and compare console capture vs appended `LOG_FILE` content. This isolation is specific to `logging.bash`.

**Session scratch:** Installer temp files use `_FILE__SESSION_ROOT` from `lib/file.bash` (initialised in `__init__` via `file__session_ensure`). In unit tests, pin paths with `export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"` — do **not** set `_FILE__SESSION_OWNED`; `file__session_cleanup` will not `rm -rf` an injected root. After `logging__cleanup`, call `file__session_cleanup` when the test created owned scratch (mirrors installer `__exit__`).

## `run` vs Direct Calls

| Situation | Approach |
|-----------|---------|
| Checking exit code or stdout | `run <function> [args]`; then `assert_success` / `assert_output` |
| Checking global state after the call | Call directly (no `run`); inspect globals afterward |
| Function modifies PATH or env | Call directly; `run` only for the return-value check |

`run` captures stdout/stderr and exit code but executes in a subshell — global state changes are invisible to the test body after `run` returns.

## Writing New Tests

1. Open (or create) `test/lib/<module>.bats`.
2. Add `reload_lib <module>.bash` (or `logging.sh` / `posix.sh`) in `setup()` unless testing idempotency.
3. Stub any external commands the function invokes.
4. Use `run` for exit-code/stdout assertions; call directly for global-state assertions.
5. One observable behaviour per `@test`.
6. Run `bash .dev/scripts/test/run-unit.sh --module <name> --jobs 1` before committing.

## Running Tests Locally

```bash
just test-lib                                        # ordinary lean in ubuntu-stable
just test-lib-integration ubuntu-stable              # ordinary integration in one platform
just test-lib-all ubuntu-stable                      # ordinary lean + integration
just test-lib-bootstrap ubuntu-stable                # dedicated fresh bare profile
just test-lib-complete ubuntu-stable                 # ordinary all then bootstrap
just test-lib-envs                                   # lean tier in all seven Linux environments
just test-lib-integration-envs                       # integration tier in all seven Linux environments
just test-lib-all-envs                               # both tiers in all seven Linux environments
just test-lib-bootstrap-envs                         # bootstrap in all seven bare profiles
just test-lib-complete-envs                          # complete workload on all seven platforms
bash .dev/scripts/test/run-unit.sh --module os       # native lean module
bash .dev/scripts/test/run-unit.sh --tier integration --module json
bash .dev/scripts/test/run-unit.sh --tier all        # native lean + integration
bash .dev/scripts/test/run-unit.sh --path test/lib/os.bats  # one exact file
bash .dev/scripts/test/run-unit.sh --filter "platform"  # filter by test-name regex
bash .dev/scripts/test/run-unit.sh --jobs 1          # serial (for debugging)
bash .dev/scripts/test/run-unit.sh --module os --jobs 4  # opt-in within-file workers
DEVFEATS_TEST_TOOL_CACHE=required test/lib/bats/bats-core/bin/bats test/lib/os.bats
```

## macOS Considerations

macOS ships bash 3.2 (GPL licence change). All `lib/` modules require bash ≥4.

`.dev/scripts/test/run-unit.sh` handles this automatically: it detects `BASH_VERSINFO[0] < 4`, finds `/opt/homebrew/bin/bash` (Apple Silicon) or `/usr/local/bin/bash` (Intel), and re-execs itself. Install bash ≥4 locally: `brew install bash`.

The macOS CI ordinary job invokes the same verified installer into a private directory under `RUNNER_TEMP`, then passes that absolute directory through `DEVFEATS_TEST_TOOL_SOURCE_DIR`. The installer selects the pinned Darwin assets directly, prepares `flock`, GPG, and XZ through Homebrew for integration prerequisites and opt-in concurrency readiness, and does not prepend the bundle to global `PATH`. Separate native macOS bootstrap isolation remains later work.

macOS-specific values to assert explicitly:

| Function | macOS value |
|----------|-------------|
| `os__kernel` | `Darwin` |
| `os__platform` | `macos` |
| `os__font_dir` (root) | `/Library/Fonts` |
| `os__font_dir` (non-root) | `${HOME}/Library/Fonts` |

macOS has no `/etc/os-release`; `os__id`, `os__id_like`, and `os__platform` fall through to the `uname -s` path.

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| `declare -A` in sourced file creates local var | All ospkg platform lookups return same value | `reload_lib` pre-declares `declare -gA _OSPKG_OS_RELEASE=()` |
| `logging__setup` hijacks fd 3 | Only 1 of N logging tests runs; bats prints "Bad file descriptor" | Wrap every logging test in `run bash -c "..."` |
| Real tool found despite fake bin prepend | Function ignores stub | Use `begin_path_isolation` to hide the real binary entirely |
| PATH left restricted after test | Bats teardown `rm: command not found` | Always `end_path_isolation` or restore PATH before function returns |
| `export -f` missing | Override invisible inside sourced library | Add `export -f <funcname>` after defining the function |
| Global state leaking between tests | Tests pass alone but fail in suite | Call `reload_lib` in `setup()` for every test needing clean state |

## CI

Library unit tests run via two jobs triggered by changes to `lib/**` or `test/lib/**`:

| Job | How it runs |
|-----|-------------|
| Linux matrix | Seven logical platform jobs. Each complete job runs ordinary lean+integration in one prepared container, then bootstrap in a separate fresh bare container: 14 concrete executions. |
| macOS | Native ordinary-suite Homebrew environments run both ordinary tiers; bash ≥4 and a private pinned Darwin test-tool bundle are prepared automatically. Separate macOS bootstrap isolation is later work. |

Local macOS runs handle the bash ≥4 requirement via the re-exec in `run-unit.sh`.
