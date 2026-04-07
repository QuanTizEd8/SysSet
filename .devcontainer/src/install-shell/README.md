# Install Shell

Install and configure Bash and Zsh with shell frameworks
([Oh My Zsh](https://ohmyz.sh/), [Oh My Bash](https://ohmybash.nntoan.com/)),
the [Starship](https://starship.rs/) prompt, and
[Nerd Fonts](https://www.nerdfonts.com/). Deploys a layered set of system-wide
and per-user configuration files that work correctly across all shell
invocation modes — login, interactive, non-interactive, scripts, cron,
`devcontainer exec`, CI runners, and VS Code tasks.

---

## Usage

### As a Dev Container feature

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/install-shell:0": {}
  }
}
```

With the defaults above, the feature will:

1. Install **Zsh** (Bash is always available)
2. Install **Oh My Zsh** with the `zsh-syntax-highlighting` plugin
3. Install **Oh My Bash** (no custom themes or plugins by default)
4. Install the **Starship** prompt binary
5. Install **Meslo** and **JetBrainsMono** Nerd Fonts
6. Deploy system-wide config files (`/etc/profile`, `/etc/shellenv`,
   `/etc/shellrc`, etc.)
7. Configure the current non-root user's dotfiles
   (`~/.bashrc`, `~/.zshrc`, `~/.shellenv`, etc.)

### Minimal example — Zsh only, no frameworks

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-shell:0": {
      "install_ohmyzsh": false,
      "install_ohmybash": false,
      "install_starship": false,
      "install_fonts": false
    }
  }
}
```

### Powerlevel10k with multi-user config

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-shell:0": {
      "ohmyzsh_theme": "romkatv/powerlevel10k",
      "ohmyzsh_plugins": "zsh-users/zsh-syntax-highlighting,zsh-users/zsh-autosuggestions",
      "set_user_shells": "zsh",
      "add_root_user_config": true,
      "add_current_user_config": true
    }
  }
}
```

### Custom installation paths

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-shell:0": {
      "ohmyzsh_install_dir": "/opt/oh-my-zsh",
      "ohmybash_install_dir": "/opt/oh-my-bash",
      "font_dir": "/opt/fonts"
    }
  }
}
```

---

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `install_zsh` | boolean | `true` | Install Zsh. Bash is always available. |
| `install_ohmyzsh` | boolean | `true` | Install Oh My Zsh. Ignored if Zsh is not available. |
| `install_ohmybash` | boolean | `true` | Install Oh My Bash. |
| `install_starship` | boolean | `true` | Install the Starship prompt binary to `/usr/local/bin`. |
| `install_fonts` | boolean | `true` | Install Nerd Fonts and refresh the font cache. |
| `ohmyzsh_theme` | string | `""` | Custom OMZ theme as a `owner/repo` GitHub slug (e.g. `romkatv/powerlevel10k`). Empty = no custom theme. |
| `ohmybash_theme` | string | `""` | Custom OMB theme as a `owner/repo` GitHub slug. Empty = no custom theme. |
| `ohmyzsh_plugins` | string | `"zsh-users/zsh-syntax-highlighting"` | Comma-separated OMZ plugins. GitHub slugs (`owner/repo`) are cloned; plain names (e.g. `git`) are treated as built-in and skipped. |
| `ohmybash_plugins` | string | `"git"` | Comma-separated OMB plugins. Same slug/built-in logic as OMZ. |
| `ohmyzsh_install_dir` | string | `"/usr/local/share/oh-my-zsh"` | Oh My Zsh installation directory (maps to the `ZSH` variable). |
| `ohmybash_install_dir` | string | `"/usr/local/share/oh-my-bash"` | Oh My Bash installation directory. |
| `ohmyzsh_custom_dir` | string | `""` | `ZSH_CUSTOM` directory. Defaults to `<ohmyzsh_install_dir>/custom`. |
| `ohmybash_custom_dir` | string | `""` | `OSH_CUSTOM` directory. Defaults to `<ohmybash_install_dir>/custom`. |
| `ohmyzsh_branch` | string | `"master"` | Git branch/tag of [ohmyzsh/ohmyzsh](https://github.com/ohmyzsh/ohmyzsh) to clone. |
| `ohmybash_branch` | string | `"master"` | Git branch/tag of [ohmybash/oh-my-bash](https://github.com/ohmybash/oh-my-bash) to clone. |
| `font_names` | string | `"Meslo,JetBrainsMono"` | Comma-separated [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts/releases) archive names to install. |
| `font_dir` | string | `"/usr/share/fonts"` | Target directory for font files. |
| `add_root_user_config` | boolean | `false` | Configure the root user's dotfiles. |
| `add_current_user_config` | boolean | `true` | Configure the current non-root user's dotfiles. |
| `add_container_user_config` | boolean | `false` | Configure the `containerUser` from devcontainer.json. |
| `add_remote_user_config` | boolean | `false` | Configure the `remoteUser` from devcontainer.json. |
| `add_user_config` | string | `""` | Comma-separated list of additional usernames to configure. |
| `user_config_mode` | string | `"overwrite"` | How to handle existing dotfiles: `overwrite`, `augment`, or `skip` (see below). |
| `set_user_shells` | string | `"none"` | Set the default login shell via `chsh`: `zsh`, `bash`, or `none`. Applies to all configured users. |
| `debug` | boolean | `false` | Enable `set -x` trace output. |
| `logfile` | string | `""` | Mirror all output (stdout + stderr) to this file. |

---

## Execution order

The installer runs as root at image build time in a single pass with nine
sequential steps.

### Bootstrap (`install.sh`)

The top-level `install.sh` is a POSIX sh script that ensures `bash` is
available (installing it via the detected package manager if necessary),
then hands off to the main orchestrator at `script/install.sh`.

### Step 1 — Install packages

Installs `zsh`, `git`, `curl`, `ca-certificates`, `fontconfig`, `xz-utils`,
and `unzip` via the `install-os-pkg` dependency (cross-distro package
installer). If `install-os-pkg` is not available, falls back to the detected
package manager directly. Skipped if `install_zsh` is `false` and all
dependencies are already present.

### Step 2 — Install Oh My Zsh

Clones [ohmyzsh/ohmyzsh](https://github.com/ohmyzsh/ohmyzsh) to the install
directory (`/usr/local/share/oh-my-zsh` by default). Sets git metadata
(`oh-my-zsh.remote`, `oh-my-zsh.branch`) so that `omz update` works.
Scaffolds the `ZSH_CUSTOM` directory structure (`themes/`, `plugins/`).
Clones any custom theme and plugins.

Skipped when `install_ohmyzsh` is `false` or Zsh is not available.

### Step 3 — Install Oh My Bash

Mirrors Step 2 for [ohmybash/oh-my-bash](https://github.com/ohmybash/oh-my-bash).
Clones the repo, sets git metadata, scaffolds `OSH_CUSTOM`, and clones custom
theme/plugins.

Skipped when `install_ohmybash` is `false`.

### Step 4 — Install Starship

Downloads and installs the [Starship](https://starship.rs/) prompt binary
using the official installer script (`https://starship.rs/install.sh`).
Idempotent — skips if the binary already exists.

Skipped when `install_starship` is `false`.

### Step 5 — Install fonts

Downloads Nerd Fonts archives (`.tar.xz`, falling back to `.zip`) from the
[ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts/releases)
releases. Each font family listed in `font_names` is extracted to a
subdirectory under `font_dir`.

When the Oh My Zsh theme is `romkatv/powerlevel10k`, the
[MesloLGS NF](https://github.com/romkatv/powerlevel10k-media) fonts required
by Powerlevel10k are installed automatically (these are custom builds by
romkatv and are **not** part of the official Nerd Fonts project).

Runs `fc-cache -f` to rebuild the font cache after installation.

Skipped when `install_fonts` is `false`.

### Step 6 — Deploy system-wide configuration files

Copies the configuration files from `files/` to their OS-detected system
locations. The installer detects the correct paths automatically:

- **Bash system bashrc**: probes `/etc/bash.bashrc` → `/etc/bashrc` →
  `/etc/bash/bashrc` (see [System path detection](#system-path-detection))
- **Zsh system directory**: probes `/etc/zsh/` → `/etc/`
- **`BASH_ENV`**: appends `BASH_ENV=<bashenv_path>` to `/etc/environment`

See [Configuration files](#configuration-files) for the full list of files
and their purposes.

### Step 7 — Resolve user list

Builds a deduplicated list of users to configure from the
`add_root_user_config`, `add_current_user_config`,
`add_container_user_config`, `add_remote_user_config`, and `add_user_config`
options. Users that do not exist on the system are skipped with a warning.

### Step 8 — Configure users

For each resolved user, copies skel dotfiles to their home directory and
injects framework configuration blocks (Oh My Zsh, Oh My Bash) into
`~/.zshrc` and `~/.bashrc` respectively. Behavior is controlled by
`user_config_mode`:

| Mode | Skel files | Framework blocks |
|---|---|---|
| `overwrite` | Replaced unconditionally | Refreshed (old block removed, new block injected) |
| `augment` | Copied only if they don't already exist | Refreshed |
| `skip` | Not touched | Not touched |

See [Per-user dotfile injection](#per-user-dotfile-injection) for details on
how the framework blocks are generated.

### Step 9 — Set default shells

When `set_user_shells` is `zsh` or `bash`, runs `chsh` for each configured
user. Automatically:

- Adds the target shell to `/etc/shells` if missing
- Fixes the PAM configuration for `chsh` on distributions where root's
  `chsh` requires a password (e.g. Alpine)

---

## Configuration files

The feature deploys a two-tier configuration architecture: **system-wide**
files in `/etc/` that establish sane defaults for all users, and
**per-user** dotfiles (skel templates) in each user's home directory.

### Design principles

1. **POSIX-first, shell-specific second.** Shared logic lives in
   `/etc/shellenv` and `/etc/shellrc` (POSIX sh), sourced by both Bash and
   Zsh. Shell-specific files delegate to these shared files, then add only
   what is unique to that shell.

2. **One-write pattern.** Environment variables (`PATH`, `XDG_*`, locale,
   editor) are set once in `/etc/shellenv` with a sentinel guard
   (`_SHELLENV_LOADED`), so they are never recomputed regardless of how many
   config files source it.

3. **Framework injection via guarded blocks.** Oh My Zsh and Oh My Bash
   configuration is injected into user dotfiles between `# BEGIN` / `# END`
   markers, not into system files. Re-running the installer with
   `user_config_mode=augment` refreshes only the marked block without
   touching user customizations outside it.

4. **Non-interactive non-login coverage.** `BASH_ENV` is set in
   `/etc/environment` so that VS Code tasks, `devcontainer exec`, CI runners,
   and other non-interactive non-login Bash sessions source the environment.

### System-wide files

| Destination | Source | Purpose |
|---|---|---|
| `/etc/shellenv` | `files/shell/shellenv` | POSIX environment: `extend_path` helper, `PATH`, `XDG_*`, locale, umask, default editor. Sourced by `/etc/profile` (sh/bash login) and `/etc/zsh/zshenv` (all zsh). |
| `/etc/shellrc` | `files/shell/shellrc` | Shared interactive config: `GPG_TTY`, VS Code editor integration, `dircolors`, `lesspipe`, `GCC_COLORS`, `command-not-found` handler. Sourced by both bashrc and zshrc. |
| `/etc/shellaliases` | `files/shell/shellaliases` | Shared aliases (`ll`, `la`, `l`). Sourced by `/etc/shellrc`. |
| `/etc/profile` | `files/profile` | Login shell profile for sh/bash. Sources `/etc/shellenv`, runs `/etc/profile.d/*.sh`, and for interactive bash sources the system bashrc. |
| `/etc/bash.bashrc`\* | `files/bash/bashrc` | Bash interactive config: prompt (`PS1`), history (append, deduplicate, timestamps), `shopt` settings, bash-completion. Sources `/etc/shellrc`. |
| `/etc/bash/bashenv`\* | `files/bash/bashenv` | Bash non-interactive environment. Sources `/etc/shellenv`. Pointed to by `BASH_ENV` in `/etc/environment`. |
| `/etc/zsh/zshenv`\* | `files/zsh/zshenv` | Sources `/etc/shellenv` via `emulate sh`. Runs for every zsh invocation. |
| `/etc/zsh/zprofile`\* | `files/zsh/zprofile` | Sources `/etc/profile` via `emulate sh`. Runs for zsh login shells. |
| `/etc/zsh/zshrc`\* | `files/zsh/zshrc` | Zsh interactive config: key bindings (terminfo-based), completion styles (`zstyle`), `compinit`, `run-help`, history settings, `COMBINING_CHARS`. Sources `/etc/shellrc`. |

\* Exact path varies by distribution — see [System path detection](#system-path-detection).

### Per-user skel files

These are copied from `files/skel/` to each configured user's home directory.

| Skel file | Purpose |
|---|---|
| `.shellenv` | User environment variables and `PATH` additions. Sourced by `.zshenv` and `.bash_profile`. Has a sentinel guard to prevent double-sourcing. Sets `XDG_*` directories. |
| `.shellrc` | User interactive config shared across bash and zsh (aliases, functions, cross-shell tool initialisers). |
| `.bash_profile` | Login shell setup for bash (and zsh via `.zprofile`). Sources `.shellenv`, then `.bashrc` (guarded by `$BASH`). |
| `.bashrc` | Bash interactive config. Contains the `# BEGIN/END install-shell-ohmybash` injection block, then sources `.shellrc`. |
| `.zshenv` | Delegates to `.shellenv` via `emulate sh`. Sets `ZDOTDIR` to `$XDG_CONFIG_HOME/zsh`. |
| `.zprofile` | Delegates to `.bash_profile` via `emulate sh` for unified login setup. |
| `.zshrc` | Zsh interactive config. Contains the `# BEGIN/END install-shell-ohmyzsh` injection block, then sources `.shellrc`. |
| `.zlogin` | Runs after `.zshrc` for login shells. Empty by default — suitable for login announcements. |

### `extend_path` helper

The `/etc/shellenv` file defines an `extend_path` function available in all
shells. It adds directories to `$PATH` without creating duplicates, silently
skips non-existent directories, and correctly handles paths with spaces.

```sh
# Prepend (inserted at front, preserving argument order):
extend_path --prepend "$HOME/.cargo/bin" "$HOME/.local/bin"

# Append (added at tail):
extend_path --append "/opt/myapp/bin"

# Both in one call:
extend_path --prepend "$HOME/bin" --append "/usr/games"
```

### Source chain

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
      ├── [OMB guarded block]
      └── ~/.shellrc (user aliases/functions)
```

**Bash non-login interactive** (e.g. opening a new terminal tab):

```
/etc/bash.bashrc
 └── /etc/shellrc → /etc/shellaliases
 └── /etc/shellenv (via sentinel re-entry)
~/.bashrc
 ├── [OMB guarded block]
 └── ~/.shellrc
```

**Bash non-interactive non-login** (e.g. `devcontainer exec`, VS Code tasks,
CI runners):

```
$BASH_ENV → /etc/bash/bashenv
 └── /etc/shellenv (PATH, XDG, locale, umask)
```

**Zsh login interactive** (e.g. `ssh`, default terminal):

```
/etc/zsh/zshenv → /etc/shellenv
~/.zshenv → ~/.shellenv
/etc/zsh/zprofile → /etc/profile → /etc/shellenv (sentinel skip) + profile.d
~/.zprofile → ~/.bash_profile → ~/.shellenv (sentinel skip)
/etc/zsh/zshrc → /etc/shellrc → /etc/shellaliases
~/.zshrc
 ├── [OMZ guarded block]
 └── ~/.shellrc
~/.zlogin
```

**Zsh non-interactive** (e.g. `zsh -c "cmd"`, scripts with `#!/usr/bin/env zsh`):

```
/etc/zsh/zshenv → /etc/shellenv
~/.zshenv → ~/.shellenv
```

---

## Per-user dotfile injection

When Oh My Zsh or Oh My Bash is installed and a user is being configured, the
installer injects a **guarded block** into the user's `~/.zshrc` or
`~/.bashrc` between `# BEGIN` and `# END` markers.

### Oh My Zsh block (`~/.zshrc`)

Injected between `# BEGIN install-shell-ohmyzsh` and
`# END install-shell-ohmyzsh`:

```bash
export ZSH="/usr/local/share/oh-my-zsh"
ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"
[ -d "$ZSH_CACHE_DIR" ] || mkdir -p "$ZSH_CACHE_DIR"
ZSH_COMPDUMP="${ZSH_CACHE_DIR}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"
ZSH_CUSTOM="$HOME/.oh-my-zsh-custom"
ZSH_THEME="powerlevel10k/powerlevel10k"      # or "" if no theme
plugins=(zsh-syntax-highlighting)              # from ohmyzsh_plugins
zstyle ':omz:update' mode disabled
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true # only when p10k theme
[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"
[[ ! -f "${HOME}/.p10k.zsh" ]] || source "${HOME}/.p10k.zsh"  # only when p10k
```

Key design decisions:

- **`ZSH_CACHE_DIR`** is set to a per-user path under `$HOME/.cache/` to
  avoid permission conflicts when multiple users share a single Oh My Zsh
  installation.
- **`ZSH_COMPDUMP`** includes `$SHORT_HOST` and `$ZSH_VERSION` to prevent
  cache corruption when the same home directory is shared across hosts or
  Zsh versions (e.g. devcontainer rebuilds).
- **`ZSH_CUSTOM`** is set to `~/.oh-my-zsh-custom` (per-user) rather than
  the shared `$ZSH/custom`, so users can add their own themes/plugins
  without root access.
- **`omz update` is disabled** because the shared installation is owned by
  root; non-root users would get `git pull` permission errors.
- **`POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true`** is set before
  sourcing `oh-my-zsh.sh` when the Powerlevel10k theme is selected, to
  prevent the interactive configuration wizard from launching on first start.

### Oh My Bash block (`~/.bashrc`)

Injected between `# BEGIN install-shell-ohmybash` and
`# END install-shell-ohmybash`:

```bash
export OSH="/usr/local/share/oh-my-bash"
OSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-bash"
[ -d "$OSH_CACHE_DIR" ] || mkdir -p "$OSH_CACHE_DIR"
OSH_CUSTOM="$HOME/.oh-my-bash-custom"
OSH_THEME=""                                   # or theme name
plugins=(git)                                   # from ohmybash_plugins
[ -f "$OSH/oh-my-bash.sh" ] && source "$OSH/oh-my-bash.sh"
```

### Re-injection behavior

When the installer runs again and the user's dotfile already contains a
guarded block, the old block is **removed** (via `sed`) and a fresh block is
**appended**. User customizations outside the markers are preserved.

The `user_config_mode` option controls this:

- **`overwrite`**: All skel files are replaced, then blocks are injected.
  Use this for a clean reset.
- **`augment`**: Skel files are copied only if they don't already exist.
  Framework blocks are always refreshed. Use this for updating framework
  config without clobbering user edits.
- **`skip`**: Nothing is touched if dotfiles already exist.

---

## Plugins and themes

### Built-in vs. custom

Plugin and theme values are classified by whether they contain a `/`:

| Value | Type | Behavior |
|---|---|---|
| `zsh-users/zsh-syntax-highlighting` | Custom (GitHub slug) | Cloned from `https://github.com/zsh-users/zsh-syntax-highlighting` |
| `git` | Built-in | Skipped — assumed to ship with the framework, no clone |

This means the default `ohmybash_plugins: "git"` works correctly: the `git`
plugin ships with Oh My Bash and does not need to be cloned.

### Custom theme resolution

When `ohmyzsh_theme` is set to a GitHub slug (e.g. `romkatv/powerlevel10k`),
the installer:

1. Clones the repository to `<ohmyzsh_custom_dir>/themes/<repo_name>/`
2. Finds the `.zsh-theme` file inside the cloned directory
3. Resolves the `ZSH_THEME` value to the `repo/stem` format that Oh My Zsh
   expects (e.g. `powerlevel10k/powerlevel10k`)

### Powerlevel10k

When the theme is `romkatv/powerlevel10k`, the installer additionally:

- Installs the **MesloLGS NF** fonts from
  [powerlevel10k-media](https://github.com/romkatv/powerlevel10k-media)
  (these are custom builds specific to p10k, not part of official Nerd Fonts)
- Sets `POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true` in the user block
- Copies `skel/p10k.zsh` to `~/.p10k.zsh` if present in the skel directory

---

## Fonts

### Nerd Fonts

The `font_names` option accepts a comma-separated list of font family names
matching the archive filenames from the
[nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts/releases)
(without the file extension). For example:

```jsonc
"font_names": "Meslo,JetBrainsMono,FiraCode,Hack"
```

Each font is downloaded as a `.tar.xz` archive (with `.zip` as a fallback),
extracted to `<font_dir>/<font_name>/`, and deduplicated against existing
installations.

### MesloLGS NF (Powerlevel10k)

The four MesloLGS NF font files required by Powerlevel10k are **separate**
from the Nerd Fonts project. They are downloaded from
[romkatv/powerlevel10k-media](https://github.com/romkatv/powerlevel10k-media)
only when `ohmyzsh_theme` contains `powerlevel10k`. These fonts are:

- MesloLGS NF Regular.ttf
- MesloLGS NF Bold.ttf
- MesloLGS NF Italic.ttf
- MesloLGS NF Bold Italic.ttf

---

## System path detection

The installer auto-detects the correct system configuration file paths for
each distribution. This is necessary because different Linux distributions
place bash and zsh config files in different locations.

### Bash system bashrc

The `detect_sys_bashrc` function probes these paths in order and returns the
first one that exists:

| Path | Distributions |
|---|---|
| `/etc/bash.bashrc` | Debian, Ubuntu, Arch, openSUSE |
| `/etc/bashrc` | Fedora, RHEL, CentOS |
| `/etc/bash/bashrc` | Gentoo, Alpine, Void |

If none exists, falls back to parsing the `strings` output of the `bash`
binary to find the compiled-in default.

### Bash bashenv

Placed next to the detected bashrc:

| Bashrc path | Bashenv path |
|---|---|
| `/etc/bash/bashrc` | `/etc/bash/bashenv` |
| `/etc/bash.bashrc` | `/etc/bashenv` |
| `/etc/bashrc` | `/etc/bashenv` |

### Zsh system directory

The `detect_zsh_etcdir` function returns:

| Path | Distributions |
|---|---|
| `/etc/zsh/` | Debian, Ubuntu, Arch, Gentoo, Alpine, Void |
| `/etc/` | Fedora, RHEL, openSUSE, macOS |

---

## `BASH_ENV`

Non-interactive non-login Bash sessions (e.g. `devcontainer exec`,
`docker exec`, VS Code tasks, CI runners) do **not** read `/etc/profile`,
`/etc/bash.bashrc`, or any dotfiles. The only mechanism for injecting
environment variables into these sessions is the `BASH_ENV` variable.

The installer sets `BASH_ENV` in `/etc/environment`, which is read by PAM
(`pam_env`), systemd, and container runtimes. This causes non-interactive
Bash to source the `bashenv` file, which in turn sources `/etc/shellenv` to
provide `PATH`, `XDG_*`, locale, and other environment variables.

> **Note:** `BASH_ENV` is honored only by Bash, not by `sh`, `dash`, or Zsh.
> For non-interactive Zsh, the `/etc/zsh/zshenv` → `/etc/shellenv` chain
> provides equivalent coverage because Zsh always reads `zshenv`.

---

## System paths summary

| Path | Purpose |
|---|---|
| `/etc/shellenv` | Shared POSIX environment (PATH, XDG, locale, umask, `extend_path`) |
| `/etc/shellrc` | Shared interactive config (GPG_TTY, editor, dircolors, aliases) |
| `/etc/shellaliases` | Shared aliases (`ll`, `la`, `l`) |
| `/etc/profile` | Login shell profile for sh/bash |
| `/etc/bash.bashrc`\* | System-wide Bash interactive config |
| `/etc/bash/bashenv`\* | `BASH_ENV` target for non-interactive Bash |
| `/etc/environment` | `BASH_ENV` variable declaration |
| `/etc/zsh/zshenv`\* | System-wide Zsh environment (all invocations) |
| `/etc/zsh/zprofile`\* | System-wide Zsh login profile |
| `/etc/zsh/zshrc`\* | System-wide Zsh interactive config |
| `/usr/local/share/oh-my-zsh/` | Oh My Zsh shared installation |
| `/usr/local/share/oh-my-bash/` | Oh My Bash shared installation |
| `/usr/local/bin/starship` | Starship binary |
| `/usr/share/fonts/` | Nerd Fonts and MesloLGS NF fonts |
| `~/.oh-my-zsh-custom/` | Per-user OMZ custom directory |
| `~/.oh-my-bash-custom/` | Per-user OMB custom directory |

\* Exact path varies by distribution.

---

## Dependencies

This feature declares a dependency on
[`install-os-pkg`](../install-os-pkg/README.md), which provides cross-distro
package installation. The following packages are installed automatically via
`packages.txt`:

| Package | Purpose |
|---|---|
| `git` | Clone OMZ, OMB, themes, and plugins |
| `curl` | Download Starship installer, Nerd Fonts, MesloLGS fonts |
| `zsh` | The Zsh shell itself |
| `ca-certificates` | HTTPS certificate validation for git/curl |
| `fontconfig` | `fc-cache` for font cache rebuilds |
| `xz-utils` | Extract `.tar.xz` font archives |
| `unzip` | Fallback extraction for `.zip` font archives |

---

## File tree

```
src/install-shell/
├── install.sh                     # POSIX sh bootstrap (ensures bash)
├── devcontainer-feature.json      # Feature metadata and options
├── packages.txt                   # OS package dependencies
│
├── script/
│   └── install.sh                 # Main orchestrator (bash, 9-step flow)
│
├── scripts/
│   ├── helpers.sh                 # Shared functions (git_clone, detect_*, etc.)
│   ├── install_ohmyzsh.sh         # Oh My Zsh: clone + theme + plugins
│   ├── install_ohmybash.sh        # Oh My Bash: clone + theme + plugins
│   ├── install_starship.sh        # Starship binary download
│   ├── install_fonts.sh           # Nerd Fonts + MesloLGS NF download
│   └── configure_user.sh          # Per-user dotfile copy + block injection
│
└── files/
    ├── profile                    # → /etc/profile
    │
    ├── shell/
    │   ├── shellenv               # → /etc/shellenv
    │   ├── shellrc                # → /etc/shellrc
    │   └── shellaliases           # → /etc/shellaliases
    │
    ├── bash/
    │   ├── bashrc                 # → /etc/bash.bashrc (or equivalent)
    │   └── bashenv                # → /etc/bash/bashenv (BASH_ENV target)
    │
    ├── zsh/
    │   ├── zshenv                 # → /etc/zsh/zshenv (or /etc/zshenv)
    │   ├── zprofile               # → /etc/zsh/zprofile
    │   └── zshrc                  # → /etc/zsh/zshrc
    │
    └── skel/
        ├── .shellenv              # → ~/.shellenv
        ├── .shellrc               # → ~/.shellrc
        ├── .bash_profile          # → ~/.bash_profile
        ├── .bashrc                # → ~/.bashrc
        ├── .zshenv                # → ~/.zshenv
        ├── .zprofile              # → ~/.zprofile
        ├── .zshrc                 # → ~/.zshrc
        ├── .zlogin                # → ~/.zlogin
        └── p10k.zsh               # → ~/.p10k.zsh (when p10k theme)
```

---

## Failure modes

The script exits non-zero (and the image build fails) when:

- It is not run as root.
- `git` or `curl` is not available after Step 1.
- A git clone fails (e.g. invalid theme/plugin slug, network failure).
- `set_user_shells` is `zsh` but Zsh is not installed.
- An unknown CLI flag is passed.
- `chsh` is not available when `set_user_shells` is not `none` (warning
  only — does not fail the build).
