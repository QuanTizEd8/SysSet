# Notes

## Configuration Files

The feature deploys a two-tier configuration architecture: **system-wide**
files in `/etc/` that establish sane defaults for all users, and **per-user**
dotfiles deployed to each configured user's home directory (and mirrored to
`/etc/skel` so future users inherit them).

### Design principles

1. **POSIX-first, shell-specific second.** Shared logic lives in
   `/etc/shellenv` and `/etc/shellrc` (POSIX sh), sourced by both Bash and
   Zsh. Shell-specific files delegate to these shared files, then add only
   what is unique to that shell.

2. **One-write pattern.** Environment variables (`PATH`, `XDG_*`, locale,
   editor) are set once in `/etc/shellenv` with a sentinel guard, so they are
   never recomputed regardless of how many config files source it. The
   per-user `~/.shellenv` uses the same pattern with its own sentinel.

3. **Theme scaffold files.** Empty theme files (by default
   `~/.config/bash/bashtheme` and `$ZDOTDIR/zshtheme`) are created as
   scaffolds for downstream features (e.g. `install-ohmyzsh`,
   `install-ohmybash`, `install-starship`), which append their own managed
   blocks to them. Pre-existing theme files are left untouched. The user
   `.bashrc`/`.zshrc` source hooks are existence-guarded, so a removed theme
   file never breaks shell startup.

4. **Non-interactive non-login coverage.** `BASH_ENV` is set in
   `/etc/environment` so that VS Code tasks, `devcontainer exec`, CI runners,
   and other non-interactive non-login Bash sessions get the shared
   environment (see [`BASH_ENV`](#bash_env) below).

### System-wide files

| Destination | Purpose |
|---|---|
| `/etc/shellenv` | POSIX environment: `extend_path` helper, `PATH`, `XDG_*`, locale, umask, default editor. Sourced by `/etc/profile` (sh/bash login), `/etc/zsh/zshenv` (all zsh), and the bashenv file. |
| `/etc/shellrc` | Shared interactive config: `GPG_TTY`, VS Code editor integration, `dircolors`, `lesspipe`, `GCC_COLORS`, `command-not-found` handler, sudo hint. Sourced by both the system bashrc and zshrc. |
| `/etc/shellaliases` | Shared aliases (`ll`, `la`, `l`). Sourced by `/etc/shellrc`. |
| `/etc/profile` | Login shell profile for sh/bash. Sources `/etc/shellenv`, runs `/etc/profile.d/*.sh`, and for interactive bash sources the system bashrc. |
| `/etc/bash.bashrc`\* | Bash interactive config: prompt (`PS1`), history, `shopt` settings, bash-completion, terminal-program hook. Sources `/etc/shellrc`. |
| `/etc/bashenv`\* | Bash non-interactive environment. Sources `/etc/shellenv`. Pointed to by `BASH_ENV` in `/etc/environment`. |
| `/etc/environment` | Carries the `BASH_ENV=…` line (managed as a single line, not a marker block). |
| `/etc/zsh/zshenv`\* | Sources `/etc/shellenv` via `emulate sh`. Runs for every zsh invocation. |
| `/etc/zsh/zprofile`\* | Sources `/etc/profile` via `emulate sh`. Runs for zsh login shells. |
| `/etc/zsh/zshrc`\* | Zsh interactive config: key bindings (terminfo-based), completion styles (`zstyle`), `compinit`, `run-help`, history, `COMBINING_CHARS`, terminal-program hook. Sources `/etc/shellrc` and the completions hook file. |
| `/etc/zsh/shellcompletions`\* | Zsh completions hook (`fpath` additions), sourced by the system zshrc right before `compinit`. A multi-writer file: downstream features (e.g. `install-zsh-completion`) append their own managed blocks. |

\* Exact path varies by distribution — see
[System path detection](#system-path-detection).

### Per-user files

Deployed to each configured user's home directory, and to `/etc/skel` as
templates for future users.

| File | Location | Purpose |
|---|---|---|
| `.shellenv` | `~/` | User environment variables and `PATH` additions (POSIX sh). Sourced by `.zshenv` and `.bash_profile`; a sentinel guard prevents double-sourcing. Sets user `XDG_*` defaults. |
| `.shellrc` | `~/` | User interactive config shared across bash and zsh (aliases, functions, cross-shell tool initialisers; POSIX sh). |
| `.bash_profile` | `~/` | Login shell setup for bash (and zsh via `.zprofile`). Sources `.shellenv`, then `.bashrc` (guarded by `$BASH`). |
| `.bashrc` | `~/` | Bash interactive config. Sources the bash theme scaffold, then `.shellrc`. |
| `.zshenv` | `~/` | Delegates to `.shellenv` via `emulate sh` and exports `ZDOTDIR`. Must live in `$HOME` so Zsh can find it before `ZDOTDIR` is set. |
| `.zprofile` | `$ZDOTDIR/` | Delegates to `.bash_profile` via `emulate sh` for unified login setup. |
| `.zshrc` | `$ZDOTDIR/` | Zsh interactive config. Sources the zsh theme scaffold, then `.shellrc`. |

### Managed marker blocks

Every configuration section the feature writes is wrapped in a marker pair:

```
# >>> setup-shell-<section> >>>
…
# <<< setup-shell-<section> <<<
```

Only the content between a block's markers is ever rewritten on re-runs
(`update` mode); everything outside the markers — distro-shipped content or
your own edits — is never touched. Disabling a section's `block_*` option
removes its marker block on the next `update` run.

### ZDOTDIR

By default Zsh looks for per-user config files (`.zshrc`, `.zprofile`) in
`$ZDOTDIR`. This feature sets `ZDOTDIR` to `~/.config/zsh` (i.e.
`${XDG_CONFIG_HOME}/zsh`), keeping Zsh dotfiles out of the home directory
root. The `.zshenv` must stay in `$HOME` so that Zsh can find it before
`ZDOTDIR` is set.

The `zdotdir` option overrides the directory. Accepted forms:

| Value | Resolved to |
|---|---|
| `""` (default) | `~/.config/zsh` |
| `~/.something` | `<user_home>/.something` (expanded per user) |
| `$HOME/.something` | `<user_home>/.something` (expanded per user) |
| `/absolute/path` | `/absolute/path` (shared across all users) |

The resolved value is exported from `~/.zshenv` inside the
`setup-shell-zdotdir` marker block.

---

## Source Chains

The following diagrams show the source chain for each shell invocation type.

**Bash login interactive** (e.g. `ssh`, `bash --login`):

```
/etc/profile
 └── /etc/shellenv (PATH, XDG, locale, umask)
 └── /etc/profile.d/*.sh
 └── /etc/bash.bashrc (if interactive)
      └── /etc/shellrc (GPG_TTY, dircolors, lesspipe, ...)
           └── /etc/shellaliases (ll, la, l)
~/.bash_profile
 └── ~/.shellenv (user PATH, XDG)
 └── ~/.bashrc
      ├── ~/.config/bash/bashtheme (downstream feature blocks)
      └── ~/.shellrc (user aliases/functions)
```

**Bash non-login interactive** (e.g. opening a new terminal tab):

```
/etc/bash.bashrc
 └── /etc/shellrc (GPG_TTY, dircolors, lesspipe, ...)
      ├── /etc/shellenv (PATH, XDG, locale, umask — first load this session)
      └── /etc/shellaliases (ll, la, l)
~/.bashrc
 ├── ~/.config/bash/bashtheme (downstream feature blocks)
 └── ~/.shellrc
```

**Bash non-interactive non-login** (e.g. `devcontainer exec`, VS Code tasks,
CI runners):

```
$BASH_ENV → /etc/bashenv
 └── /etc/shellenv (PATH, XDG, locale, umask)
```

**Zsh login interactive** (e.g. `ssh`, default terminal):

```
/etc/zsh/zshenv → /etc/shellenv
~/.zshenv → ~/.shellenv + exports ZDOTDIR=~/.config/zsh
/etc/zsh/zprofile → /etc/profile → /etc/shellenv (sentinel skip) + profile.d
$ZDOTDIR/.zprofile → ~/.bash_profile → ~/.shellenv (sentinel skip)
/etc/zsh/zshrc → /etc/shellrc → /etc/shellaliases
 └── /etc/zsh/shellcompletions (fpath) → compinit
$ZDOTDIR/.zshrc
 ├── $ZDOTDIR/zshtheme (downstream feature blocks)
 └── ~/.shellrc
```

**Zsh non-interactive** (e.g. `zsh -c "cmd"`, scripts with
`#!/usr/bin/env zsh`):

```
/etc/zsh/zshenv → /etc/shellenv
~/.zshenv → ~/.shellenv + exports ZDOTDIR (not used in non-interactive)
```

---

## System Path Detection

The installer auto-detects the correct system configuration file paths for
each distribution, since different Linux distributions place bash and zsh
config files in different locations. Detection is driven by the OS-release
platform ID (`ID`/`ID_LIKE`), **not** by probing for whichever file happens to
already exist — a config file written to the wrong path for the distro would
never be sourced by any shell.

### Bash system bashrc

Chosen from the resolved platform tag:

| Path | Platforms |
|---|---|
| `/etc/bashrc` | Fedora, RHEL, CentOS, Rocky, AlmaLinux, openSUSE, SLES, macOS |
| `/etc/bash/bashrc` | Alpine |
| `/etc/bash.bashrc` | Debian, Ubuntu, Arch, Gentoo, Void, and any other Linux (default) |

### Bash bashenv

Placed next to the detected bashrc (override with `sys_bashenv`):

| Bashrc path | Bashenv path |
|---|---|
| `/etc/bash/bashrc` | `/etc/bash/bashenv` |
| `/etc/bash.bashrc` | `/etc/bashenv` |
| `/etc/bashrc` | `/etc/bashenv` |

### Zsh system directory

Location of the system `zshenv`, `zprofile`, `zshrc`, and the
`shellcompletions` hook file. Detected primarily by reading the global
`zshenv` path compiled into the `zsh` binary; when `zsh` is unavailable, the
platform tag is used as a fallback:

| Path | Platforms (fallback) |
|---|---|
| `/etc/zsh/` | Debian, Ubuntu, Arch, Gentoo, Alpine, Void |
| `/etc/` | Fedora, RHEL, CentOS, openSUSE, macOS |

---

## `BASH_ENV`

Non-interactive non-login Bash sessions (e.g. `devcontainer exec`,
`docker exec`, VS Code tasks, CI runners) do **not** read `/etc/profile`,
the system bashrc, or any dotfiles. The only mechanism for injecting
environment variables into these sessions is the `BASH_ENV` variable.

The installer sets `BASH_ENV` in `/etc/environment`, which is read by PAM
(`pam_env`), systemd, and container runtimes. This causes non-interactive
Bash to source the bashenv file, which in turn sources `/etc/shellenv` to
provide `PATH`, `XDG_*`, locale, and other environment variables.

> **Note:** `BASH_ENV` is honored only by Bash, not by `sh`, `dash`, or Zsh.
> For non-interactive Zsh, the `/etc/zsh/zshenv` → `/etc/shellenv` chain
> provides equivalent coverage because Zsh always reads `zshenv`.

---

## `extend_path` Helper

The `/etc/shellenv` file defines an `extend_path` function available in all
shells (including your own `~/.shellenv`). It adds directories to `$PATH`
without creating duplicates, silently skips non-existent directories, and
correctly handles paths with spaces. Run `extend_path --help` for details.

```sh
# Prepend (inserted at front, preserving argument order):
extend_path --prepend "$HOME/.cargo/bin" "$HOME/.local/bin"

# Append (added at tail):
extend_path --append "/opt/myapp/bin"

# Both in one call:
extend_path --prepend "$HOME/bin" --append "/usr/games"
```
