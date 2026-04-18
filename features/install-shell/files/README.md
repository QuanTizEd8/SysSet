# Shell Configuration Files

This directory contains the system-wide and per-user skeleton shell configuration
files installed by the `install-shell` package.

---

## Directory Structure

```
files/
├── shell/
│   ├── shellenv        → /etc/shellenv
│   ├── shellrc         → /etc/shellrc
│   └── shellaliases    → /etc/shellaliases
├── bash/
│   ├── bashenv         → /etc/bash/bashenv  (or /etc/bashenv)
│   └── bashrc          → /etc/bash/bashrc   (or /etc/bash.bashrc)
├── zsh/
│   ├── zshenv          → /etc/zsh/zshenv
│   ├── zprofile        → /etc/zsh/zprofile
│   └── zshrc           → /etc/zsh/zshrc
├── profile             → /etc/profile
└── skel/
    ├── .shellenv       → /etc/skel/.shellenv  (copied to ~/.shellenv)
    ├── .shellrc        → /etc/skel/.shellrc   (copied to ~/.shellrc)
    ├── .bash_profile   → /etc/skel/.bash_profile
    ├── .bashrc         → /etc/skel/.bashrc
    ├── .zshenv         → /etc/skel/.zshenv
    ├── .zprofile       → /etc/skel/.zprofile
    ├── .zshrc          → /etc/skel/.zshrc
    └── .zlogin         → /etc/skel/.zlogin
```

Files under `skel/` are copied verbatim to a new user's home directory by
`useradd`/`adduser` at account creation time.

---

## Design Principles

- **POSIX throughout**: all files in `shell/` and `skel/` that are shared
  across shells use only POSIX sh syntax. Shell-specific syntax is confined to
  `bash/`, `zsh/`, and the zsh-only parts of `skel/` (`.zshrc`, etc.).
- **Single source of truth**: shared logic lives in exactly one file. Each
  shell-specific file is a thin wrapper that delegates to the shared file.
- **Idempotent**: sentinel variables (`_SHELLENV_LOADED`, `_USER_SHELLENV_LOADED`)
  prevent double-sourcing when multiple startup files would otherwise source the
  same file in the same session.
- **Non-destructive guards**: environment variables set by the caller or a parent
  process are preserved (`${VAR:-default}` pattern).
- **Portable tool detection**: hardcoded tool paths (`/usr/bin/dircolors`) are
  avoided; `command -v` is used to find tools wherever they are installed.

---

## System-Level Files

### `shell/shellenv` → `/etc/shellenv`

The single source of truth for **system-wide environment variables**. Must be
POSIX sh compatible — it is sourced by `emulate sh` in zsh contexts.

Contains:
- `extend_path` — a POSIX PATH helper that adds directories without duplicates,
  handles spaces, and preserves argument order. Calls `export PATH` internally.
- `umask 022`
- `USER` and `HOME` guards for minimal environments (e.g. `su` without `-l`)
- macOS `path_helper` invocation (guarded by `[ -x /usr/libexec/path_helper ]`)
- Baseline `PATH` covering `/usr/local/{s,}bin`, `/usr/{s,}bin`, `/{s,}bin`;
  `/usr/games` for non-root; `$HOME/.local/bin` and `$HOME/bin` prepended
- XDG Base Directory variables (all with `${VAR:-default}` guards)
- `LANG` and `LC_ALL` defaults (`en_US.UTF-8`, guarded)
- `VISUAL` / `EDITOR` defaults (nano if available, otherwise vi, guarded)

### `shell/shellrc` → `/etc/shellrc`

System-wide **interactive shell configuration** shared across bash and zsh.
Guarded by `case $- in *i*)` — silently ignored in non-interactive contexts.

Contains:
- Sources `/etc/shellenv` (no-op if already loaded via login shell)
- GPG TTY setup: `export GPG_TTY="${TTY:-$(tty)}"` + `gpg-connect-agent updatestartuptty`
- VS Code editor detection: sets `VISUAL`/`EDITOR` to `code --wait` or
  `code-insiders --wait` when `$TERM_PROGRAM=vscode`, using
  `$VSCODE_GIT_ASKPASS_MAIN` for stable/Insiders detection
- `LS_COLORS` via `dircolors` / `gdircolors` (with `~/.dircolors` override)
- `ls` color aliases (`--color=auto` for GNU, `-G` for BSD/macOS, runtime-tested)
- `grep`/`fgrep`/`egrep` color aliases (runtime-tested)
- `lesspipe` / `lesspipe.sh` setup (whichever is available)
- `GCC_COLORS` for colourised compiler diagnostics
- `command_not_found_handle` (bash) and `command_not_found_handler` (zsh)
  delegating to a shared `_command_not_found_handler` function
- Sudo hint (one-time reminder for users in the `sudo`/`admin` group)
- Default `PROMPT` / `PS1` (shell-type detected via `$ZSH_VERSION`)
- Sources `/etc/shellaliases`

### `shell/shellaliases` → `/etc/shellaliases`

System-wide aliases sourced by `shellrc` for both shells:

| Alias | Expands to |
|-------|-----------|
| `ll` | `ls -alF` |
| `la` | `ls -A` |
| `l`  | `ls -CF` |

### `profile` → `/etc/profile`

POSIX login shell entry point (`sh`, `bash --login`, `dash`, etc.).

- Sources `/etc/shellenv`
- Iterates `/etc/profile.d/*.sh` (using `run-parts` if available, otherwise
  POSIX glob)
- For bash login shells: sources `/etc/bash/bashrc` (falling back to
  `/etc/bash.bashrc`, then `/etc/bashrc` for Alpine/RHEL)
- For `sh`: sets a minimal `PS1` (`#` for root, `$` otherwise)

### `bash/bashenv` → `/etc/bash/bashenv`

Thin wrapper sourced for non-interactive bash env scripts (`BASH_ENV`). Sources
`/etc/shellenv` to ensure PATH and XDG are set.

### `bash/bashrc` → `/etc/bash/bashrc`

System-wide bash interactive configuration.

- Interactivity guard
- Sources `/etc/shellrc`
- Default `PS1='\\u@\\h:\\w\\$ '`
- History: `HISTIGNORE`, `HISTCONTROL`, `HISTSIZE`, `HISTFILESIZE`,
  `HISTTIMEFORMAT`, `PROMPT_COMMAND` (append + reload across sessions),
  `histappend`
- `checkwinsize` to keep `LINES`/`COLUMNS` current
- Bash completion (from `/usr/share/bash-completion/bash_completion` or
  `/etc/bash_completion`)
- Terminal program integration hook: sources
  `bashrc_$TERM_PROGRAM` from the same directory if present

### `zsh/zshenv` → `/etc/zsh/zshenv`

Sourced for **every** zsh invocation. Sets environment via:
```zsh
emulate sh -c 'source "/etc/shellenv"'
```

### `zsh/zprofile` → `/etc/zsh/zprofile`

Sourced for zsh **login** shells (before `zshrc`). Runs `/etc/profile` via:
```zsh
emulate sh -c 'source "/etc/profile"'
```

### `zsh/zshrc` → `/etc/zsh/zshrc`

System-wide zsh interactive configuration.

- Interactivity guard
- UTF-8 combining character support (`COMBINING_CHARS`)
- Sources `/etc/shellrc`
- `READNULLCMD` pager setup
- Key bindings: terminfo-driven Home/End/Insert/Delete/PageUp/PageDown; Up/Down
  bound to `up-line-or-search` / `down-line-or-search`; PageUp/PageDown to
  `history-beginning-search-backward` / `history-beginning-search-forward`
- Completion styles (`zstyle`) and `compinit` (sets `skip_global_compinit=1`
  so oh-my-zsh does not call `compinit` a second time)
- `run-help` autoload
- History options: `HISTSIZE`, `SAVEHIST`, `HISTFILE`, `histignorealldups`,
  `sharehistory`, `extended_history`, `hist_ignore_space`
- Default `PROMPT='%n@%m:%~%# '`
- Terminal program integration hook: sources `zshrc_$TERM_PROGRAM` if present

---

## User Skeleton Files (`skel/`)

Copied to `~/` when a new user account is created. The architecture mirrors the
system-level design: shared logic lives in `.shellenv` / `.shellrc`; each
shell's files are thin wrappers.

### `.shellenv`

User-specific environment variables and PATH additions, read by all shells.
Write only POSIX sh syntax. A sentinel (`_USER_SHELLENV_LOADED`) prevents
double-sourcing.

Intended content: `extend_path` calls for personal tools (cargo, go, pyenv),
API keys, tool-specific exports.

### `.shellrc`

User-specific interactive configuration shared across bash and zsh. Guarded
by `case $- in *i*)`. Write only POSIX sh syntax.

Intended content: personal aliases, POSIX-compatible functions, cross-shell
tool initialisers (e.g. `zoxide init posix`).

### `.bash_profile`

Bash login shell entry point. Sourced by `.zprofile` via `emulate sh`, so it
must remain POSIX-compatible.

- Sources `~/.shellenv`
- Sources `~/.bashrc` — guarded by `[ "${BASH-}" ]` so the guard fires only
  in real bash, never when `.zprofile` sources this file in zsh

### `.bashrc`

User-specific bash interactive configuration.

- Interactivity guard
- Sources `~/.shellrc`
- User's bash-specific overrides below (history tuning, prompt themes, etc.)

### `.zshenv`

Sourced for every zsh invocation. Delegates to `~/.shellenv` via `emulate sh`
so the sentinel in `.shellenv` prevents double-sourcing.

### `.zprofile`

Zsh login shell entry point. Delegates to `~/.bash_profile` via `emulate sh`.
The `$BASH` guard in `.bash_profile` ensures `.bashrc` is not loaded.

Intended content: login-once setup — `ssh-agent`, `keychain`, macOS GUI vars.

### `.zshrc`

User-specific zsh interactive configuration. Contains the oh-my-zsh block
(theme, plugins, options). Sources `~/.shellrc` after `oh-my-zsh.sh` so user
aliases and functions can override framework defaults.

### `.zlogin`

Sourced last in the zsh login shell sequence (after `.zshrc`). Appropriate for
login announcements, `fortune`, session-level health checks. Empty by default.

---

## Execution Flows

### Bash — interactive login shell (`ssh`, `su -l`, terminal app)

```
/etc/profile
  └── /etc/shellenv               (PATH, XDG, LANG, EDITOR, umask)
  └── /etc/profile.d/*.sh
  └── /etc/bash/bashrc
        └── /etc/shellrc          (GPG, editor, colors, aliases, prompt)
              └── /etc/shellenv   (no-op: sentinel)
              └── /etc/shellaliases

~/.bash_profile
  └── ~/.shellenv                 (user PATH, tokens — no-op if already loaded)
  └── ~/.bashrc
        └── ~/.shellrc            (user aliases, functions)
```

### Bash — interactive non-login shell (new terminal tab)

```
/etc/bash/bashrc
  └── /etc/shellrc
        └── /etc/shellenv
        └── /etc/shellaliases

~/.bashrc
  └── ~/.shellrc
```

### Bash — non-interactive login (`bash --login -c "cmd"`, BASH_ENV)

```
/etc/profile → /etc/shellenv      (PATH, XDG set)
~/.bash_profile → ~/.shellenv     (no-op)
~/.bashrc                         (interactivity guard fires — returns immediately)
```

### Zsh — interactive login shell

```
/etc/zsh/zshenv
  └── /etc/shellenv               (via emulate sh)

/etc/zsh/zprofile
  └── /etc/profile                (via emulate sh)
        └── /etc/shellenv         (no-op: sentinel)
        └── /etc/profile.d/*.sh

/etc/zsh/zshrc
  └── /etc/shellrc
        └── /etc/shellenv         (no-op)
        └── /etc/shellaliases

~/.zshenv
  └── ~/.shellenv                 (via emulate sh)

~/.zprofile
  └── ~/.bash_profile             (via emulate sh)
        └── ~/.shellenv           (no-op: sentinel)
        ($.bashrc NOT sourced — $BASH guard blocks it)

~/.zshrc
  └── oh-my-zsh
  └── ~/.shellrc

~/.zlogin                         (announcements, etc.)
```

### Zsh — interactive non-login shell

```
/etc/zsh/zshenv → /etc/shellenv
/etc/zsh/zshrc  → /etc/shellrc → /etc/shellenv (no-op) → /etc/shellaliases
~/.zshenv       → ~/.shellenv
~/.zshrc        → oh-my-zsh → ~/.shellrc
```

### Zsh — non-interactive (script, cron, `zsh -c "cmd"`)

```
/etc/zsh/zshenv → /etc/shellenv   (PATH, XDG set — no output, no tty)
~/.zshenv       → ~/.shellenv
(zshrc, zprofile NOT sourced)
```

### `sh` — login shell (`/bin/sh`, POSIX script)

```
/etc/profile
  └── /etc/shellenv
  └── /etc/profile.d/*.sh
  └── PS1='$ ' (or '#' for root)
```

---

## Key Design Decisions

### `extend_path` in `/etc/shellenv`

A POSIX PATH helper that:
- Skips non-existent directories silently
- Deduplicates against existing `PATH` entries
- Preserves argument order for both `--prepend` and `--append`
- Handles directory names with spaces via newline-only IFS splitting
- Calls `export PATH` at the end so callers never need to

### VS Code shell integration

`shellrc` detects `$TERM_PROGRAM=vscode` and sets `VISUAL`/`EDITOR` to
`code --wait` (or `code-insiders --wait`). `git` picks this up automatically via
`$VISUAL` without needing a separate `GIT_EDITOR` export.

No themes are applied at the system level. This prevents conflicts with VS Code
shell integration, which depends on OSC 633 sequences that prompt themes
frequently suppress or overwrite.

### No system-level prompt theme

Prompt themes are intentionally absent from the system config. They conflict with
VS Code's shell integration protocol (OSC 633 sequences for command detection),
causing Copilot terminal tools to hang indefinitely. A minimal `PS1`/`PROMPT` is
set in `shellrc` as a fallback; users install their preferred theme in
`~/.zshrc` or `~/.bashrc`.

### `emulate sh` in zsh wrappers

The system zsh files (`zshenv`, `zprofile`) and user files (`.zshenv`,
`.zprofile`) use `emulate sh -c 'source ...'` to source the shared POSIX files.
This ensures zsh's extended syntax (arrays, `[[`, `typeset`) cannot interfere
with POSIX sh files, and that POSIX scripts sourced this way behave identically
in both shells.

### Sentinel guards

Both `/etc/shellenv` (`_SHELLENV_LOADED`) and `~/.shellenv` (`_USER_SHELLENV_LOADED`)
use a sentinel to prevent double-sourcing. This matters for zsh login shells
where `zshenv → shellenv` and `zprofile → profile → shellenv` would otherwise
run it twice.
