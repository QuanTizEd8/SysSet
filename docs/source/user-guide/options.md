# Feature Options

Features provide a rich set of options to customize their behavior. All options have sensible defaults, so you only need to explicitly set the ones you want to customize.

## Input Modes

Options can be set via different mechanisms depending on the installation method, but they all share the same names and semantics across channels. For the full list of available options for each feature, see the reference documentation on each feature's page in the [Features](/features.md) section.

### Dev Container

In Dev Containers, each feature's options are defined in the `devcontainer.json` file's `features.<feature-id>.options` object – the value of the feature ID key in the `features` object. The dev container tooling automatically gathers these options and injects them as environment variables when invoking the feature's installer script.

```jsonc
{
  // devcontainer.json
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user": {
      "username": "myusername",
      "user_id": "1000"
    }
  }
}
```

### CLI

When using SysSet or invoking the installer script directly, options can be passed as CLI flags with the form `--<option_name> <value>`, passed after the feature ID. The CLI flag spelling matches the option name verbatim (no hyphenation):

```sh
# Using SysSet:
sysset feat install ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user \
  --username myusername \
  --user_id 1000

# Directly invoking the installer:
sh setup-user/install.sh \
  --username myusername \
  --user_id 1000
```

:::{admonition} Environment Variables
:class: note dropdown

To be Dev Container Feature compliant, all features also support reading options from environment variables, which is how dev container tooling delivers them. Environment variables take the form `<OPTION_NAME>=<value>` and are set before invoking the installer:

```sh
USERNAME=myusername \
USER_ID=1000 \
sh setup-user/install.sh
```

However, this type of delivery is discouraged outside of dev container features, as it is more error-prone (e.g. an unrelated existing environment variable with the same name as a feature option can cause unintended configuration). Therefore, to avoid unexpected interactions, features only read options from environment variables when no CLI flags are provided at all. Even a single CLI flag for any option will disable environment variable parsing for all options in that invocation, causing any options not explicitly set via CLI flags to fall back to their defaults.
:::


## Option Types

Each option has one of the following types, which determines how it is set in each channel and how the installer receives it. The type of each option is documented on its reference page.

### String

String options take a single arbitrary string value. Depending on the context, the string may be interpreted as a literal value (e.g. a username), or parsed according to some rules (e.g. a version string that accepts `latest` and semver ranges); it may also contain special characters and whitespace (e.g. a multi-line shell command).

::::{tab-set}

:::{tab-item} Dev Container
```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git": {
      "version": "2.54.0"
    }
  }
}
```
:::

:::{tab-item} CLI

```sh
sh install-git/install.sh \
  --version "2.54.0"
```
:::

:::{tab-item} Env Var

```sh
VERSION="2.54.0" sh install-git/install.sh
```
:::

::::


### Enum

Enum options are just like string options, but their allowed values are constrained to a specific set (e.g. `log_level` can only be `silent`, `error`, `warn`, `info`, `debug`, or `trace`).

### Boolean

Boolean options are set to either `true` or `false`. The value is always explicit — there are no bare on/off flags, so on the CLI you write `--<option> true`, not a lone `--<option>`.

::::{tab-set}

:::{tab-item} Dev Container
```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git": {
      "keep_cache": true
    }
  }
}
```
:::

:::{tab-item} CLI

```sh
sh install-git/install.sh \
  --keep_cache true
```
:::

:::{tab-item} Env Var

```sh
KEEP_CACHE=true sh install-git/install.sh
```
:::

::::

### Array

DevFeats extends the standard devcontainer feature option schema with an internal **array** type (serialized as `string` in the generated `devcontainer-feature.json`, so spec tooling accepts it). It lets a feature take a list of values ergonomically in every invocation channel. Array elements can be either strings or enums. Some options of this type also support single sentinel values (e.g. `auto`) that resolves to a default array based on the context. An empty string input corresponds to an empty array. Inside the installer, the variable is always a bash array, regardless of which channel populated it.

::::{tab-set}

:::{tab-item} Dev Container

Since `devcontainer.json` only supports string and boolean types, array options are represented as multi-line strings with newline-delimited values (with leading/trailing whitespace trimmed and empty lines ignored).

```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-fonts": {
      "nerd_fonts": "Meslo\nFiraCode"
    }
  }
}
```
:::

:::{tab-item} CLI

In the CLI, array options are set by repeating the corresponding flag for each element (each `--<flag> <value>` pair **appends** one element to the array):

```sh
sh install-fonts/install.sh \
  --nerd_fonts Meslo \
  --nerd_fonts FiraCode
```
:::

:::{tab-item} Env Var

Similarly to `devcontainer.json`, array option can be set via environment variable by using a newline-delimited string. In bash, this can be done with ANSI-C quoting (`$'...'`):

```sh
NERD_FONTS=$'Meslo\nFiraCode' sh install-fonts/install.sh
```

In POSIX shells that don't support ANSI-C quoting, you can use a literal multi-line string:

```sh
NERD_FONTS="Meslo
FiraCode" sh install-fonts/install.sh
```
:::

::::


## Common Options

Some options are **shared across features**, with the same names and semantics everywhere, so you can rely on them working the same way in every feature that supports them. Which of these a feature actually exposes depends on what it does — for example, only features that offer more than one installation strategy have a `method` option, and only features that install a versioned tool have a `version` option. The canonical set of shared options and their defaults is defined once in [`features/metadata.shared.yaml`](https://github.com/|{{github_user}}|/|{{github_repo}}|/blob/main/features/metadata.shared.yaml); each feature's exact option list, types, and defaults are on its reference page in the [Features](/features.md) section. This section describes the most common ones by semantics; consult the feature page for concrete values.

### Tool Version

The **`version`** option selects which version of the underlying tool a feature installs. This is the *tool* version, not the feature's own release version — see [Feature Version ≠ Tool Version](versioning.md#feature-version-tool-version). It is present only on features that install a versioned tool. Accepted spellings depend on the feature's upstream source, but generally include:

- **`stable`** *(usual default)* — the newest stable (non-pre-release) version.
- **`latest`** — the newest version, **including** pre-releases.
- **a partial or full version** (`1`, `1.2`, `1.2.3`, `1.2.3-rc1`) — the newest version matching that prefix.
- **source-specific forms** — e.g. npm dist-tags (`next`), or a git branch/tag/commit for features installed from source.

See the feature's reference page for its accepted values. Advanced overrides (`version_uri`, `version_resolution`, `version_flag`, `version_tag_prefix`, `version_pattern`) let you redirect version resolution to a mirror, proxy, or private registry.

### Installation Method

The **`method`** option chooses *how* a feature installs its tool. It appears only when a feature offers **more than one** method; single-method features have no `method` option. The default, **`auto`**, selects the best method that is feasible on the current OS, architecture, and privilege level. Concrete values are per-feature (e.g. `binary`, `package`, `upstream-package`, `source`, `cargo`, `npm`, `script`, `git-clone`); see the feature's reference page for which methods it supports and when each is preferred.

### Re-runs & Idempotency

The **`if_exists`** option *(enum, default `skip`)* controls what happens when the tool is already installed:

- **`skip`** — leave the existing installation untouched (default; makes re-runs cheap).
- **`fail`** — abort with an error.
- **`reinstall`** — remove the existing installation and install fresh.
- **`update`** — resolve the requested version and switch to it if it differs from what's installed.
- **`uninstall`** — remove the tool.

Because installers guard already-completed work, re-running one after fixing an environment issue is safe and does not require uninstalling first.

### Install Location & Scope

Features that lay down files under a prefix expose a family of options controlling **where** the tool is installed and **how** it is exposed on `PATH`:

- **`prefix`** — the install prefix. It defaults to a system location when running as root (e.g. `/usr/local`) and to a per-user location otherwise (e.g. `~/.local`), so the same feature adapts to system-wide vs. user-scoped installs automatically.
- **`prefix_discovery`** *(`auto`/`symlink`/`shell`/`all`/`none`)* — how the tool's binaries are put on `PATH`: by symlinking them into a bin directory already on `PATH`, by writing shell `PATH` exports, both, or neither.
- **`prefix_symlinks`, `prefix_exports`, `prefix_bins`, `prefix_bin_dir`, `prefix_symlink_root`, `prefix_symlink_nonroot`, `runtime_path`** — fine-grained control over the symlink targets, exported shells, and the `PATH` used to decide whether the prefix is already reachable.
- **`write_group`, `write_users`, `install_user`** — for a tool installed once but shared by several users, these control the OS group that owns the prefix and which users may write to it.

See [Environment Variables](../background/env-vars.md) and [Shell Configuration](../background/shell-config.md) for the underlying `PATH` and shell-startup mechanics these options drive.

### User Configuration

Features that write **per-user** configuration (e.g. shell setup or `git` config) expose options selecting which users to configure:

- **`add_current_user`** *(default `true`)* — the invoking user (or `SUDO_USER`).
- **`add_remote_user`** *(default `true`)* — the dev container's remote user.
- **`add_container_user`** *(default `true`)* — the dev container's container user.
- **`add_users`** — additional usernames to configure.

### Shell Completions

The **`shell_completions`** option *(array)* selects which shells to install command-line completions for (e.g. `bash`, `zsh`, `fish`), for features whose tool ships completion scripts.

### Logging

All features support emitting logs to the console (diagnostic stream on stderr) and/or to a file, with independent verbosity thresholds and known secrets redacted on write. Log lines are prefixed with emojis to indicate their level (grep for `❌` / `⛔` in a log file to jump straight to failures). Three options control logging:

- **`log_level`** *(string, default `"info"`)* — minimum level for the **console**. Levels (in increasing verbosity):
  - `silent`: only fatal errors (❌)
  - `error`: above plus non-fatal errors (⛔)
  - `warn`: above plus warnings (⚠️)
  - `info`: above plus general info (ℹ️)
  - `debug`: above plus debug messages (🐞) and installer subprocess stdout/stderr
  - `trace`: above plus `bash -x` / xtrace lines routed through the same ordered capture path
- **`log_file`** *(string, default `""`)* — when set to a file path, the session journal is **appended** here on exit (mkdir -p on the parent directory). Empty means no file capture; `log_file_level` is ignored. Fatal lines are always written when a log file is configured, even if `log_file_level` is `silent`. Append-safe across features in the same run.
- **`log_file_level`** *(string, default `"debug"`)* — minimum level for the **file** when `log_file` is set. Same level names as `log_level`. Use a quieter `log_level` and a more verbose `log_file_level` to keep the terminal readable while retaining a detailed log.

**Dual thresholds:** Console and file each apply their own filter. A line may appear on one sink only (e.g. `log_level=warn`, `log_file_level=debug` → debug structured lines only in the file).

**Ordering:** Events appear in the same **execution order** on both sinks for lines that are emitted. Lines present on both console and file are not reordered relative to each other (interleaved structured messages, subprocess output, and xtrace share one ordered journal).

**Output classes:**

| Class | Level tier | Gating |
|-------|------------|--------|
| `logging__fatal` | 0 | Always on console; always in file when `log_file` is set |
| Structured helpers (`logging__error` … `logging__debug`, phase helpers) | 1–4 | Per sink threshold |
| Installer subprocess stdout/stderr (and children inheriting redirected fds) | 4 (`debug`) | Per sink; requires `debug` or `trace` on that sink |
| `set -x` / xtrace | 5 (`trace`) | Per sink; `trace` on console and/or file enables xtrace independently |

### Caching

All features provide a `keep_cache` boolean option that controls whether package manager caches are kept after installation (e.g. `apt` cache on Debian-based systems, `dnf` cache on RedHat-based systems, `conda` cache when using Conda). This is `false` by default to save disk space and keep image layers smaller, but can be set to `true` when you want to keep the cache for faster subsequent installs or when installing outside of a container where layer size is not a concern.

### Build Tools

Most features depend on tools to download files (e.g. `curl`, `wget`, `git`), extract archives (e.g. `tar`, `unzip`), parse JSON API responses (e.g. `jq`), build from source (e.g. `make`, `cmake`), and more. These are not runtime dependencies of the installed features, but they are required to perform the installation. By default, the installer attempts to detect which tools are available in the environment and use them accordingly. If any required tool is missing, the installer will install it automatically and mark it for removal at the end of the installation to avoid leaving unnecessary packages on the system. However, you can also choose to keep them by setting `keep_build_deps` to `true`. This is useful to speed up subsequent installs of other features that use the same tools, at the cost of leaving them on the system.

### Repositories

Features that install their tool from a third-party package repository (e.g. an APT or DNF repo, a Homebrew tap, or a PPA) expose a **`keep_repos`** boolean option *(default `false`)*. When `false`, the added repository and its signing key are removed after installation to leave the system clean. Set it to `true` to keep them registered so the tool can later be upgraded with the system package manager.

### Fetching User-Provided Files

Features that accept file inputs by URI (e.g. a config file or key) expose **`fetch_headers`** and **`fetch_netrc`** for authenticated downloads, and **`installer_dir`** to control the working directory used to download and extract installation artifacts (a temporary directory by default).


## Secrets

Some features support options that are secrets (e.g. tokens, passwords, private keys). These are always only accepted via environment variables, regardless of the installation channel, and are always masked in the captured log stream. They include:

- `GITHUB_TOKEN` *(optional)*: If set, used to authenticate GitHub API calls and `ghcr.io` OCI pulls (avoids anonymous rate limits). `GH_TOKEN` is accepted as a fallback when `GITHUB_TOKEN` is unset.

::::{tab-set}

:::{tab-item} Dev Container

```jsonc
{
  "build": {
    "dockerfile": "Dockerfile",
    "args": { "GITHUB_TOKEN": "${localEnv:GITHUB_TOKEN}" }
  },
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-miniforge": {
      "version": "26.1.1-3"
    }
  }
}
```
:::

:::{tab-item} Env Var


```sh
GITHUB_TOKEN=ghp_1234567890abcdef \
sh install-miniforge/install.sh \
  --version 26.1.1-3
```
:::

::::
