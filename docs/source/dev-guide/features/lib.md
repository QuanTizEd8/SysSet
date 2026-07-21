# Shared Library

The `lib/` directory contains reusable bash modules covering OS detection, package installation, GitHub API calls, checksum verification, user management, shell configuration, and more. During `just sync-src`, `lib/` is copied into each feature's `src/*/lib/`, making every feature tarball self-contained. All library functions are available in `install.bash` without any explicit `source` call — the installer framework automatically sources `lib/__init__.bash`, which loads all modules.

> **Always check here before implementing something from scratch.** If a function does what you need, use it. If you are writing logic that could benefit other features, add it to `lib/` instead of keeping it inline.

## Module Conventions

Every module contains **only function definitions and inert module-global declarations** — no top-level executable code. Because of this:

- The whole library is sourced **once**, as a unit, by `lib/__init__.bash` (which the installer framework sources for you). Module load **order does not matter**, and there is **no double-source guard** — none is needed.
- All library functions are available in `install.bash`, and in other modules, without any explicit `source`.

**Naming.** Public functions are named `module__function` (e.g. `os__platform`, `shell__sync_config`); private helpers are `_module__function`; module-global variables are `_MODULE__NAME` (upper-case). This namespacing is what lets every module load into one shell without collisions.

**Local variables.** Function-scoped variables must be declared `local` (or `declare`). This is enforced by the `lint-sh-local-vars` check (part of `just lint`); only `ALL_CAPS` names and `_<MODULE>__`-prefixed globals are exempt (with per-case suppressions in `.config/lib-local-vars.allowlist`).

**POSIX vs bash.** Most modules are bash and use the `.bash` extension. Two modules — **`logging.sh`** and **`posix.sh`** — are POSIX `sh` because they run during the bootstrap phase (`install.sh`), before a bash ≥ 4.4 is guaranteed to exist.

**Non-shell assets.** `lib/` also ships files that are copied into each feature but are **not** auto-documented: the `.jq` filters (`ctx-match.jq`, `ctx-when-eval.jq`, `ospkg-manifest.jq`), `argparse-manifest.schema.json`, the vendored ospkg manifests under `lib/deps/`, and `lib/metadata.yaml` (library package metadata, used by `just build-lib`).

**Testing.** Every public function is covered by the BATS unit suite under `test/lib/`. Run `just test-lib` to verify changes locally before pushing. See {doc}`/dev-guide/tests/lib` for how to write new tests.

**Multi-value conventions.** Many helpers return multiple logical items as one stdout line per item (empty list → no output). This composes naturally with pipes, `while read -r`, and `mapfile`.

## Network retry contract

Network operations owned by the shared library use `lib/net.bash` as their
transport boundary. Use `net__fetch_url_stdout` or `net__fetch_url_file` for
HTTP downloads rather than invoking `curl` or `wget` directly. Because a fetch
is idempotent, they retry by default—including unknown statuses such as `404`
that can result from CDN or registry propagation—and honor `Retry-After`. They
only fail fast for clear local/request failures such as malformed URLs,
authentication failures, and certificate-validation errors. File
downloads use a temporary payload and replace the destination only after a
successful fetch.

Use `net__fetch_with_retry --retry-if <classifier>` for idempotent commands
whose client is not `curl` or `wget`, such as Git and ORAS. The classifier
receives the exit code and a file containing stderr; it should return success
only for errors that are safe to retry. Package-manager installation and
repository operations go through the shared package-manager wrapper for the
same reason.

The retry budget can be adjusted for constrained environments with
`DEVFEATS_NET_FETCH_RETRIES`, `DEVFEATS_NET_FETCH_DELAY`, and
`DEVFEATS_NET_FETCH_MAX_DELAY`. HTTP transfers also accept
`--connect-timeout` and `--max-time`; callers that cannot pass flags directly
can set `DEVFEATS_NET_FETCH_CONNECT_TIMEOUT` and
`DEVFEATS_NET_FETCH_MAX_TIME`. Curl applies the latter as a per-attempt transfer
ceiling; wget, which has no equivalent whole-transfer option, maps it to its
network-operation timeout. Neither value caps the whole retry sequence. Tests
that intentionally exercise unreachable network paths should use
`lib_test__net_fetch_fail_fast`; real-network integration tests should use the
bounded helper matching their client.

Feature-specific installers may invoke clients that perform their own network
operations, such as npm, Cargo, nvm, conda, rustup, or `gh extension install`.
Those calls require client-specific retry handling and are not safe to wrap
blindly in the generic command helper: a client may leave partial installation
state or use an exit status that does not distinguish transport from
configuration errors. Such paths must either use the client's native retry
controls or receive a dedicated, idempotent adapter.

## Documentation

Each shell module in `lib/` (`*.bash` plus the small POSIX `*.sh` subset) is automatically parsed and rendered into an API reference page under `docs/source/library/<module-filename>.md`. The generator reads structured comments — no external tools required. This section explains what to write so that the output renders correctly.

### Module header

A module has **no shebang** (it is sourced, not executed); its first line is a `# shellcheck shell=bash` directive. The leading comment block after that directive becomes the module's page header: the **first non-empty comment line** is the one-line summary (used in the library index card), and everything after the first blank comment line is the long description.

```bash
# shellcheck shell=bash
# One-line summary of the module.
#
# Longer description. May span multiple lines and contain
# light Markdown formatting.
```

Both the summary and the long description are optional. A module without a summary still gets its own API reference page (all `@brief` function annotations are rendered), but it is omitted from the library index and a warning is printed to stderr.

### Function annotations

All functions — public and private — should use the `# @brief` format. The generator filters out private functions (names starting with `_`) by default; pass `--include-private` to `proman-gen-docs-data` to include them.

**`@brief` line format:**

```
# @brief <signature> — <one-line description>.
```

- `<signature>` is the full call signature: function name followed by any positional arguments, flags, or metavariables (e.g. `json__root_scalar_stdin <key>` or `logging__info <line>...`).
- The separator between signature and description must be an em-dash (`—`, U+2014). A space-hyphen-space (` - `) is also accepted but the em-dash is preferred.
- The function name is taken as the first whitespace-delimited word of `<signature>`.

**Body blocks** follow the `@brief` line. By convention the whole annotation block is the **first thing inside the function body** (the parser also accepts it immediately above the definition). All contiguous comment lines are collected; blank comment lines (`#` on its own) act as block separators.

```bash
myfunc() {
  # @brief myfunc <arg> — Short description.
  #
  # Optional paragraph with more detail.
  # Can span multiple lines.
  #
  # Args:
  #   <arg>        What the argument means.
  #   --flag <v>   What the flag does.
  #
  # Env:
  #   MY_VAR  Environment variable description.
  #
  # Stdout: what is printed to stdout.
  #
  # Returns: exit codes and their meaning.
  ...
}
```

### Body block types

The generator classifies each block (group of lines between blank comment lines) into one of two types:

**Paragraph block** — plain prose. Rendered as a paragraph of text.

```bash
# All arguments are forwarded to `jq` unchanged.
```

**Section block** — a labelled heading. Two forms are recognised:

| Form | Syntax | When to use |
|------|--------|-------------|
| Multi-item | `Label:` on its own line; each item indented by **≥ 2 spaces** | `Args:` / `Parameters:` / `Env:` |
| Inline | `Label: text` as the **only line** in the block | `Stdout:` / `Returns:` |

The label must start with an uppercase letter and contain only letters (`[A-Za-z]+`) followed by a colon. Recognised labels and how they render:

| Comment label | Rendered heading | Rendered style |
|---------------|------------------|----------------|
| `Args:` | **Parameters** | Definition list |
| `Parameters:` | **Parameters** | Definition list |
| `Env:` | **Environment** | Definition list |
| `Stdout:` | **Stdout** | Plain text |
| `Returns:` | **Returns** | Plain text |

Any other `Word:` label is passed through as-is.

**Definition list items** (under `Args:` / `Parameters:` / `Env:`) are split into name and description on **two or more consecutive spaces**. The name is wrapped in backticks; the description becomes the definition term body.

```bash
# Args:
#   <key>         Top-level object key to extract.
#   --verbose     Print extra diagnostics.
```

Renders as:

```markdown
### Parameters

`<key>`
: Top-level object key to extract.

`--verbose`
: Print extra diagnostics.
```

### Rendered output structure

For reference, the full structure the generator produces for a module:

```markdown
# `<module-filename>`

<module summary>

<module long description>

## `<function-name>`

<one-line description from @brief>

`​`​`bash
<signature>
`​`​`

<paragraph blocks>

### Parameters

`<name>`
: <description>

### Environment

`<VAR>`
: <description>

### Stdout

<inline text>

### Returns

<inline text>
```

Functions appear in source order. A function with no body blocks after its `@brief` line produces only the heading, description, and signature code block.
