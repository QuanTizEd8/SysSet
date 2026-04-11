---
description: "Use when writing or editing bats unit tests for lib/ modules under test/unit/. Covers the bats framework, reload_lib helper, the declare -gA ospkg workaround, command stubs, subprocess isolation for logging, macOS bash ≥4 requirements, and common pitfalls."
applyTo: "test/unit/**"
---

# Lib Unit Tests (bats)

Unit tests for `lib/` live under `test/unit/`. Each `.bats` file covers one module.

Tests run without Docker by sourcing lib files directly into the bats test process. The full suite runs on both Linux and macOS in CI.

## Vendor Libraries

bats-core and its companion libraries are git submodules at `test/unit/bats/`. Initialise once after cloning:

```bash
git submodule update --init --recursive
```

Never edit files under `test/unit/bats/` — they are vendored.

| Submodule | Purpose |
|---|---|
| `bats-core` | Test runner |
| `bats-support` | Failure output formatting |
| `bats-assert` | `assert_success`, `assert_output`, etc. |
| `bats-file` | `assert_file_exists`, `assert_dir_exists`, etc. |

## File Anatomy

```bash
# Load bats companion libraries BEFORE any `load` calls.
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# Load project helpers.
load helpers/common   # provides reload_lib()
load helpers/stubs    # provides create_fake_bin(), prepend_fake_bin_path()

# Reload the library under test before each test for a clean state.
setup() {
  reload_lib os.sh
}

@test "os::kernel returns the uname output" {
  uname() { printf 'Linux\n'; }
  export -f uname
  run os::kernel
  assert_success
  assert_output "Linux"
}
```

## reload_lib

**`reload_lib <module.sh>`** — defined in `helpers/common.bash`. Call it in `setup()` to give every test a clean module state. It:

1. Clears all `_LIB_*_LOADED` guard variables so the module re-sources.
2. Unsets all cached globals (`_OS_KERNEL`, `_NET_FETCH_TOOL`, `_OSPKG_DETECTED`, etc.).
3. For `ospkg.sh` specifically: pre-declares `_OSPKG_OS_RELEASE` as a **global** associative array with `declare -gA` **before** sourcing — see [ospkg.sh scoping workaround](#ospkgsh-scoping-workaround).
4. Sources `${LIB_ROOT}/<module.sh>`.

```bash
setup() {
  reload_lib ospkg.sh   # works for any module
}
```

To test the load-guard (idempotency), call `reload_lib` in `setup()` then source the file directly inside the test without calling `reload_lib` again — the guard variable will prevent re-sourcing.

### ospkg.sh Scoping Workaround

`ospkg.sh` contains `declare -A _OSPKG_OS_RELEASE=()`. When a file is sourced from **within a bash function**, `declare` without `-g` creates a **local** variable that disappears when the function returns. Without the workaround, every test that relies on `_OSPKG_OS_RELEASE` after `reload_lib` returns would see an undeclared variable — bash silently treats it as an indexed array, all non-integer keys map to `[0]`, and the last write wins (typically the arch value from `uname -m`).

`reload_lib` pre-empts this by running `declare -gA _OSPKG_OS_RELEASE=()` before the `source` call. The global declaration ensures the array exists at the correct scope. Always use `reload_lib` rather than sourcing `ospkg.sh` directly in test setup.

## Stubbing Commands

`helpers/stubs.bash` provides two helpers:

```bash
# Create ${BATS_TEST_TMPDIR}/bin/<name> — prints <stdout> and exits 0.
create_fake_bin "curl" "fake-response"
create_fake_bin "apt-get" ""          # prints nothing

# Prepend fake bin dir to PATH so fakes shadow real commands.
prepend_fake_bin_path
```

Stubs are scoped to `$BATS_TEST_TMPDIR`, which bats cleans up after each test.

### Replacing PATH Entirely

When the real command must be completely hidden — for example, testing wget detection while `curl` is installed on the host:

```bash
@test "detects wget when curl is absent" {
  reload_lib net.sh
  create_fake_bin "wget" ""
  local _saved="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin"   # only fake bin — real curl invisible
  net::ensure_fetch_tool
  local _result="$_NET_FETCH_TOOL"
  export PATH="$_saved"                   # restore before bats teardown uses rm, etc.
  [[ "$_result" == "wget" ]]
}
```

**Always restore PATH before the test function returns.** Bats teardown uses `rm` and other tools that require a real PATH. If PATH is left restricted, bats prints `rm: command not found` warnings during cleanup (tests still pass, but the output is noisy).

## Overriding Commands with Shell Functions

bash built-ins and external commands can be overridden by defining a function with the same name:

```bash
uname() { printf 'Darwin\n'; }
export -f uname   # make visible in sourced files
```

`export -f` is required whenever the function must be visible inside a sourced library file. Without it, the library's call to the command resolves to the real binary.

For commands where a function override is awkward (requires parsing arguments), prefer `create_fake_bin` + `prepend_fake_bin_path` instead.

## Mocking Library Functions

To mock a lib function called by the function under test, define it in the test body before invoking the real function:

```bash
@test "github::latest_tag parses tag_name from JSON" {
  reload_lib net.sh
  reload_lib github.sh
  github::fetch_release_json() {
    printf '{"tag_name":"v1.2.3"}\n'
    return 0
  }
  export -f github::fetch_release_json
  run github::latest_tag "owner/repo"
  assert_success
  assert_output "v1.2.3"
}
```

## Subprocess Isolation for `logging.sh`

`logging::setup` executes `exec 3>&1 4>&2`, which redirects file descriptor 3. Bats uses fd 3 for TAP output — the redirect corrupts bats' reporting and causes most tests in the file to silently vanish.

**Rule:** Every test that calls `logging::setup` or `logging::cleanup` must run in a `bash -c` subprocess isolated from bats' fd 3:

```bash
@test "logging::setup creates a temp log file" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    logging::setup
    [[ -f \"\${_LOGGING_TMPFILE}\" ]] && echo OK
  "
  assert_success
  assert_output "OK"
}
```

This isolation is specific to `logging.sh`. Other modules do not need it.

## Using `run` vs Direct Calls

| Situation | Approach |
|---|---|
| Checking exit code or stdout | `run <function> [args]`; then `assert_success` / `assert_output` |
| Checking global state after the call | Call directly (no `run`); inspect globals afterward |
| Function modifies PATH or env | Call directly; inspect with `[[ ... ]]`; use `run` only for the return-value check |

`run` captures stdout/stderr and the exit code but executes in a subshell — changes to exported variables or global state are invisible to the test body after `run` returns.

## Writing New Tests

1. Open `test/unit/<module>.bats` for the module you changed.
2. Add `reload_lib <module>.sh` in `setup()` unless the test explicitly checks idempotency.
3. Stub any external commands the function invokes.
4. Use `run` for exit-code / stdout assertions; call directly for global-state assertions.
5. One observable behaviour per `@test`.
6. Run `bash test/run-unit.sh --module <name> --jobs 1` before committing.

## Running Tests Locally

```bash
# All modules (also runs sync-lib.sh first)
make test-unit

# Single module
bash test/run-unit.sh --module os

# Filter by test name (regex)
bash test/run-unit.sh --filter "platform"

# Serial output — useful for debugging
bash test/run-unit.sh --jobs 1

# Direct bats invocation — skips sync-lib.sh, useful for iteration
test/unit/bats/bats-core/bin/bats test/unit/os.bats
```

## macOS Considerations

macOS ships bash 3.2 due to the GPL licence change in bash 4+. All lib/ modules require bash ≥4.

`test/run-unit.sh` handles this automatically:

1. Detects `BASH_VERSINFO[0] < 4`.
2. Tries `/opt/homebrew/bin/bash` (Apple Silicon) then `/usr/local/bin/bash` (Intel).
3. Re-execs itself under the first bash ≥4 found.
4. Prepends that executable's directory to `PATH` so `#!/usr/bin/env bash` sub-scripts (bats-exec-test, bats-exec-suite) also resolve to bash ≥4.

Install bash ≥4 locally: `brew install bash`. The CI `macos-latest` runner has Homebrew bash pre-installed.

macOS-specific return values to test for explicitly:

| Function | macOS value |
|---|---|
| `os::kernel` | `Darwin` |
| `os::platform` | `macos` |
| `os::font_dir` (as root) | `/Library/Fonts` |
| `os::font_dir` (non-root, no `$XDG_DATA_HOME`) | `${HOME}/Library/Fonts` |

macOS has no `/etc/os-release`, so `os::id`, `os::id_like`, and `os::platform` fall through to the `uname -s` path.

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| `declare -A` in sourced file creates local var | All ospkg platform lookups return the same value | `reload_lib` pre-declares `declare -gA _OSPKG_OS_RELEASE=()` before sourcing |
| `logging::setup` hijacks fd 3 | Only 1 of N logging tests runs; bats prints "Bad file descriptor" | Wrap every logging test in `run bash -c "..."` |
| Real `curl` found despite fake bin prepend | `net::ensure_fetch_tool` always returns `curl` even in the wget test | Replace PATH entirely (`export PATH="${BATS_TEST_TMPDIR}/bin"`); restore afterward |
| PATH left restricted | Bats teardown `rm: command not found` | Always `export PATH="$_saved"` before the test function returns |
| `export -f` missing | Overridden function invisible inside sourced library | Add `export -f <funcname>` after defining the override |
| Global state leaking between tests | Tests pass individually but fail in suite | Call `reload_lib` in `setup()` for every test that needs a clean module state |
