# `install.sh` (Bootstrap)

The [Dev Container specification](https://containers.dev/implementors/features/#invoking-installsh) requires every feature to have an `install.sh` at its root. Supporting tools set the execute bit on this file and invoke it directly as the feature entry point.

## Purpose

`install.sh` is a minimal POSIX `sh` script — not bash — to ensure it works in any environment, including those where a modern bash is not yet installed. Its only job is to:

1. Ensure **`bash` ≥ 4.4** is present, and
2. Hand off execution to `install.bash` (the real installer written in bash ≥ 4.4).

To obtain a compatible bash it tries, in order: the shell already running the script, a `bash` on `PATH`, then — if neither qualifies — installing one via the OS package manager, or compiling it from source as a last resort. This layered bootstrap is what lets a single installer run on minimal images (e.g. Alpine with busybox `sh`).

The bootstrap's network operations are retry-aware. Downloads use the atomic
POSIX fetch helper in `lib/posix.sh`; package-manager update/install commands
use `posix__run_with_retry`, which captures both output streams and retries all
nonzero package-manager failures unless a diagnostic proves a local source-list
or command-invocation error. This also catches the repository/transport errors
that APT and DNF can report while returning exit status zero. Package-manager
retry settings are independent from direct downloads: use
`DEVFEATS_OSPKG_RETRIES` (default `5`) and `DEVFEATS_OSPKG_RETRY_DELAY`
(default `10` seconds).

## Source of Truth

There is a **single source of truth** at `features/install.sh`. During `just sync-src`, this file is copied verbatim to every `src/*/install.sh`. **Never edit `src/*/install.sh` directly** — it is overwritten on every sync.

To change the bootstrap logic, edit `features/install.sh` and run `just sync-src`.
