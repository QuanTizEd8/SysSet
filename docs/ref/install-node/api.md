# API Reference — install-node

<!-- START devcontainer-feature.json MARKER -->
<!-- This section will be automatically generated from devcontainer-feature.json, containing the feature description and options table. Do not rewrite manually. -->
<!-- END devcontainer-feature.json MARKER -->

Install Node.js and npm in the development container. Two methods are supported, selected by the `method` option:

- **`nvm`** (default) — installs the Node Version Manager (nvm) to `nvm_dir` and uses it to install the requested Node.js version. Supports Linux (glibc and musl/Alpine), macOS, and any POSIX platform.
- **`binary`** — downloads the official prebuilt Node.js tarball from `nodejs.org/dist` and extracts it to `prefix`. Fast and dependency-free. NOT compatible with Alpine Linux (musl).

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `method` | string (enum) | `"nvm"` | Installation method: `"nvm"` or `"binary"`. |
| `version` | string (proposals) | `"lts/*"` | Node.js version: `"lts/*"`, `"lts"` (alias), `"latest"`, `"none"`, major number, or exact semver. |
| `additional_versions` | string | `""` | Comma-separated extra Node.js versions to install via nvm (not set as default). `method=nvm` only. |
| `nvm_version` | string (proposals) | `"latest"` | nvm version to install (`method=nvm` only). |
| `nvm_dir` | string | `"/usr/local/share/nvm"` | nvm installation directory (`method=nvm` only). |
| `prefix` | string | `"auto"` | Installation prefix for binaries (`method=binary` only). |
| `arch` | string | `""` | Override CPU architecture for binary selection (`method=binary` only). |
| `installer_dir` | string | `"/tmp/node-installer"` | Temp directory for downloads. |
| `if_exists` | string (enum) | `"skip"` | Behavior when node already exists: `"skip"`, `"fail"`, or `"reinstall"`. |
| `export_path` | string | `"auto"` | Controls which shell files receive PATH exports. |
| `add_current_user_config` | boolean | `true` | Include the current user in the resolved user list for group membership and per-user shell RC PATH writes. Root is deferred: only included as a fallback when no other non-root user is resolved. |
| `add_remote_user_config` | boolean | `true` | Include the devcontainer remoteUser (from `_REMOTE_USER`) in the resolved user list. Ignored when `_REMOTE_USER` is unset or empty. Root is excluded. |
| `add_container_user_config` | boolean | `true` | Include the devcontainer containerUser (from `_CONTAINER_USER`) in the resolved user list. Ignored when `_CONTAINER_USER` is unset or empty. Root is excluded. |
| `add_user_config` | string | `""` | Comma-separated list of additional usernames for the resolved user list. Root is accepted here. |
| `set_permissions` | boolean | `true` | Create nvm group, set group-write/setgid on `nvm_dir`, run installer as user (`method=nvm` only). |
| `group` | string | `"nvm"` | Group name for nvm directory ownership (`method=nvm`, `set_permissions=true`). |
| `symlink` | boolean | `true` | For nvm (root only): creates a bridge symlink `/usr/local/share/nvm → nvm_dir` so that `containerEnv.NVM_DIR` and `containerEnv.PATH` stay valid when `nvm_dir` is non-default. `NVM_SYMLINK_CURRENT=true` is always enabled. For binary: root symlinks `node`, `npm`, `npx`, `corepack` into `/usr/local/bin` when `prefix` is not `/usr/local`; non-root symlinks them into `$HOME/.local/bin` when `prefix` is not `$HOME/.local`. |
| `node_gyp_deps` | boolean | `true` | Install `make`, `gcc`/`g++`, `python3` for compiling native modules (node-gyp). |
| `pnpm_version` | string (proposals) | `"none"` | pnpm version to install globally (`"none"` to skip, `"latest"`, or explicit version). |
| `yarn_version` | string (proposals) | `"none"` | Yarn version to install globally (`"none"` to skip, `"latest"` via corepack, or explicit version). |
| `debug` | boolean | `false` | Enable debug output (`set -x`). |
| `logfile` | string | `""` | Append install log to this file path. |

---

## Usage Examples

### Basic: Latest LTS via nvm (default)

The simplest use — installs the latest Active LTS Node.js release using nvm with all defaults:

```jsonc
// devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {}
  }
}
```

Equivalent standalone invocation:
```bash
curl -fsSL https://get.sysset.dev | bash -s -- install-node
```

### Pin a Specific Node.js Version

Install an exact Node.js version using the binary method (fastest, no nvm overhead):

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "method": "binary",
      "version": "22.15.1"
    }
  }
}
```

Standalone:
```bash
curl -fsSL https://get.sysset.dev | bash -s -- install-node --method binary --version 22.15.1
```

### Pin a Major LTS Line

Install the latest release in the v22 "Jod" LTS line:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "version": "22"
    }
  }
}
```

### Alpine Linux (nvm with Source Compilation)

Alpine requires `method=nvm` (the default). The installer automatically switches to
`nvm install -s 'lts/*'` and installs all build dependencies via apk:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "method": "nvm",
      "version": "lts/*"
    }
  }
}
```

> **Note:** Compilation takes ~10–20 minutes on Alpine. `method=binary` will exit with an error on Alpine — always use `method=nvm` for Alpine-based images.

### Custom nvm Directory and Version

Install nvm v0.40.4 (pinned) to a custom directory. Because `symlink=true` (the default),
the installer creates a symlink `/usr/local/share/nvm` → `/opt/nvm`—so `containerEnv.NVM_DIR` stays valid automatically:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "method": "nvm",
      "nvm_version": "0.40.4",
      "nvm_dir": "/opt/nvm",
      "version": "22"
    }
  }
}
```

Standalone:
```bash
curl -fsSL https://get.sysset.dev | bash -s -- install-node \
  --method nvm --nvm_version 0.40.4 --nvm_dir /opt/nvm --version 22
```

### Binary Method with Custom Install Prefix

Install the Node.js binary to `/opt/node` with a symlink in `/usr/local/bin`:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "method": "binary",
      "version": "24",
      "prefix": "/opt/node",
      "symlink": true
    }
  }
}
```

### Multi-User PATH Configuration

Export the PATH for the devcontainer remote user in addition to system-wide files:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:2": {
      "method": "binary",
      "version": "lts/*",
      "add_remote_user_config": true
    }
  }
}
```

### Skip PATH Modification

When your image already has `/usr/local/bin` on PATH and `symlink=true` (the default) is sufficient,
disable redundant PATH writes:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "export_path": ""
    }
  }
}
```

### Force Reinstall

Reinstall Node.js even if it's already present in PATH:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "if_exists": "reinstall",
      "version": "22"
    }
  }
}
```

### Install pnpm and Yarn

Install both pnpm and Yarn alongside Node.js:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "version": "22",
      "pnpm_version": "latest",
      "yarn_version": "latest"
    }
  }
}
```

Standalone:
```bash
curl -fsSL https://get.sysset.dev | bash -s -- install-node \
  --version 22 --pnpm_version latest --yarn_version latest
```

### Multiple Node.js Versions

Install v22 as default and also install v20 and v18 (for cross-version testing):

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "version": "22",
      "additional_versions": "20,18"
    }
  }
}
```

### Skip node-gyp Build Tools

For minimal images where native module compilation is not needed:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "version": "lts/*",
      "node_gyp_deps": false
    }
  }
}
```

### nvm Only (No Node.js Version)

Install nvm without installing any Node.js version — useful when a `.nvmrc` or postCreateCommand handles version selection:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "version": "none"
    }
  }
}
```

---

## Details

### Version Format

| Input | Resolved to | Works with `method=nvm`? | Works with `method=binary`? |
|---|---|---|---|
| `"lts/*"` | Latest Active LTS | ✅ (passed to nvm directly) | ✅ (resolved from index.json) |
| `"lts"` | Alias for `"lts/*"` | ✅ (normalized internally) | ✅ (normalized internally) |
| `"latest"` / `"node"` | Latest Node.js | ✅ | ✅ (resolved from index.json) |
| `"none"` | No Node.js installed | ✅ (nvm only) | ❌ (not applicable) |
| `"22"` (major only) | Latest v22.x | ✅ | ✅ (resolved from index.json) |
| `"22.15.1"` / `"v22.15.1"` | Exact version | ✅ | ✅ |
| `"lts/jod"` (codename) | Latest v22.x (Jod) | ✅ | ❌ (nvm-specific alias) |

> **Shell quoting:** The value `lts/*` requires quoting in shell contexts to prevent glob expansion. The installer handles this internally; you do not need to add quotes in `devcontainer.json` or CLI flag values.

### Alpine Linux Limitations

- `method=binary` **does not work on Alpine**. The official Node.js prebuilt binaries are linked against glibc and are incompatible with Alpine's musl libc. The script exits with an actionable error message on Alpine.
- `method=nvm` compiles Node.js from source using `nvm install -s`. Build dependencies (`curl bash ca-certificates openssl ncurses coreutils python3 make gcc g++ libgcc linux-headers grep util-linux binutils findutils`) are installed automatically from the apk dependency manifest.
- Compilation takes approximately 10–20 minutes on Alpine.
- On Alpine 3.5–3.12 (legacy), `python2` is used instead of `python3`, and only older Node.js versions are supported (see the [nvm Alpine docs](https://github.com/nvm-sh/nvm#installing-nvm-on-alpine-linux) for version support matrix).

### PATH Availability

**`method=nvm`:**
- In devcontainers, `containerEnv.PATH` includes `/usr/local/share/nvm/current/bin`, which resolves through the `$NVM_DIR/current` symlink (maintained by `NVM_SYMLINK_CURRENT=true`) to the active Node.js version's bin directory. `node`, `npm`, `npx`, and `corepack` are available to all container processes without any extra configuration.
- In bare-metal and login-shell contexts (without `containerEnv`), `export_path=auto` writes an nvm initialisation snippet to system-wide shell startup files:
  - `/etc/profile.d/nvm_init.sh` (login shells)
  - System-wide bashrc (non-login interactive bash)
  - `<zshdir>/zshenv` (all zsh sessions, system-wide)
  - BASH_ENV file registered in `/etc/environment` (non-interactive Docker `RUN` steps)
- The snippet sources `$NVM_DIR/nvm.sh`, which activates the `nvm` command and sets `PATH` to the currently active version's bin directory via the `current` symlink. This means `nvm use <version>` immediately switches the active version in all new shell sessions — no PATH hardcoding.

**`method=binary`:**
- When `prefix=auto` (→ `/usr/local`): binaries land in `/usr/local/bin`, which is universally on PATH. No PATH writes are needed; `containerEnv.PATH` covers the container.
- When `prefix` is a custom path: `export_path=auto` writes `export PATH="<prefix>/bin:${PATH}"` to the same system-wide files listed above, ensuring availability in all contexts.

### NVM_SYMLINK_CURRENT and Version Switching

The feature sets `NVM_SYMLINK_CURRENT=true` in both `containerEnv` and the nvm init snippet written to shell startup files. This causes nvm to maintain a `$NVM_DIR/current` symlink that always points to the active Node.js version directory. The `containerEnv.PATH` includes `/usr/local/share/nvm/current/bin`, making the active version's binaries available to all container processes.

Key behaviors:
- Running `nvm use <version>` inside the container automatically updates the `current` symlink, switching the active version for all new shells without rerunning the installer.
- The installer sets `NVM_SYMLINK_CURRENT=true` before running `nvm install`, so `current` is created during installation.
- For `method=nvm`, no manual per-binary symlinks to `/usr/local/bin` are needed — the `current/bin` path covers everything.
- The nvm init snippet written to shell startup files (`/etc/profile.d/nvm_init.sh`, `.bashrc`, `.zshenv`, etc.) also exports `NVM_SYMLINK_CURRENT=true`, ensuring this behavior is preserved in bare-metal and non-container shell sessions where `containerEnv` is not active.

### NVM_DIR Container Environment

The feature sets `NVM_DIR=/usr/local/share/nvm` in `containerEnv`. This means:
- All container processes have `NVM_DIR` pointing to the standard nvm location.
- Sourcing `$NVM_DIR/nvm.sh` activates the `nvm` command for in-container use.
- When `nvm_dir` is overridden and `symlink=true` (the default), the installer creates
  `ln -sf <nvm_dir> /usr/local/share/nvm`, so both `containerEnv.NVM_DIR` and
  `containerEnv.PATH` remain correct without any extra user configuration.
- If `symlink=false` and `nvm_dir` is not `/usr/local/share/nvm`, you must manually
  override `NVM_DIR` in your `devcontainer.json` `containerEnv`:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-node:1": {
      "nvm_dir": "/opt/nvm",
      "symlink": false
    }
  },
  "containerEnv": {
    "NVM_DIR": "/opt/nvm",
    "PATH": "/opt/nvm/current/bin:/usr/local/bin:${PATH}"
  }
}
```

### Group Permissions and Non-Root nvm Access

`set_permissions=true` (the default for `method=nvm`) ensures:
1. A group (`group`, default: `nvm`) is created.
2. `nvm_dir` is owned by the nvm group with group-write and setgid bits (`g+rws`).
3. All resolved users (from `add_current_user_config`, `add_remote_user_config`, `add_container_user_config`, and `add_user_config`) are added to the group.
4. The nvm installer and `nvm install` are executed as the first resolved user via `su $USER -c "..."` with `umask 0002`, so all installed files are group-writable.

This means non-root container users can freely run `nvm install <version>`, `nvm use <version>`, and `nvm ls` inside the running container without `sudo`.

Set `set_permissions=false` to skip group setup and run the installer as root (legacy/simple mode).

### node-gyp Build Dependencies

`node_gyp_deps=true` (the default) installs `make`, `gcc`, `g++`, and `python3` via the OS package manager — the tools required to compile native Node.js addons (e.g. `bcrypt`, `node-canvas`, `sharp`, `sqlite3`). On Alpine Linux with `method=nvm`, these are already part of the nvm source-build toolchain and are never duplicated.

Set `node_gyp_deps=false` for minimal images where only pure-JS packages are used.

### pnpm and Yarn

Both `pnpm_version` and `yarn_version` default to `"none"` (not installed). Set them to `"latest"` or an explicit version string to install globally after Node.js.

- **pnpm:** installed via `npm install -g pnpm@<VERSION>`.
- **yarn `"latest"`:** uses `corepack enable` (preferred for Yarn 2/3/4, ships with Node.js 16+). Falls back to `npm install -g yarn` if corepack is unavailable.
- **yarn explicit version** (e.g. `"1.22.22"`): installs via `npm install -g yarn@<VERSION>` (classic Yarn 1.x).

### Additional Node.js Versions

`additional_versions` accepts a comma-separated list of node version specs (same syntax as `version`). Each extra version is installed via `nvm install` without setting it as default. Post-install, `nvm use default` restores the primary version as active. This option is only applicable for `method=nvm`.

> **Note:** If `version=none` is combined with `additional_versions`, no default alias is set. The versions will be available but `nvm` will require an explicit version for `nvm use`. Run `nvm alias default <version>` manually inside the container to set a default.

### Security: Binary Verification

When using `method=binary`, the installer:
1. Downloads `node-v{VERSION}-{PLATFORM}.tar.xz` from `https://nodejs.org/dist/`
2. Downloads `SHASUMS256.txt` from the same dist directory
3. Verifies the SHA-256 checksum of the tarball against `SHASUMS256.txt`

> **Limitation:** `SHASUMS256.txt` is GPG-signed by the Node.js release team (sidecar files `.sig` and `.asc` are available on nodejs.org/dist). This feature verifies the SHA-256 checksum only — it does NOT verify the GPG signature of `SHASUMS256.txt`. HTTPS transport to `nodejs.org` provides a baseline integrity guarantee.

### nvm Binary Security

When using `method=nvm`, the nvm install script is downloaded from a pinned tagged URL (`https://raw.githubusercontent.com/nvm-sh/nvm/v{TAG}/install.sh`). This URL is tied to a specific commit on GitHub; HTTPS transport to `raw.githubusercontent.com` provides a baseline integrity guarantee. The nvm install script itself is **not** verified with a SHA-256 checksum — the nvm project does not publish a `SHASUMS` file for `install.sh`. Node.js binaries subsequently downloaded by nvm are verified by nvm’s own internal checksum mechanism against `SHASUMS256.txt`.

### `if_exists` Behavior

| `if_exists` | Node already installed | Version matches | Behavior |
|---|---|---|---|
| `"skip"` | No | — | Proceed with install |
| `"skip"` | Yes | Yes | Silent skip (always, regardless of setting) |
| `"skip"` | Yes | No | Log notice, skip, exit 0 |
| `"fail"` | Yes | No | Log error, exit non-zero |
| `"reinstall"` | Yes | No | Remove existing, install fresh |

> **Note:** The `update` value (upgrade to a newer version without full reinstall) is intentionally absent. For `method=binary`, use `if_exists=reinstall` to switch versions. For `method=nvm`, `nvm install <version>` is idempotent — re-run the installer with a new `version` value to add a version alongside the existing one.

### `export_path` Details

| Value | Effect |
|---|---|
| `"auto"` (default) | Write PATH export to all system-wide shell startup files (root) or user-scoped RC files (non-root). |
| `""` (empty) | Skip all PATH/shell writes. |
| Newline-separated absolute paths | Write only to the listed files. |

With `method=binary` and `prefix=auto` (resolving to `/usr/local`) and `symlink=true`, the binaries already land in `/usr/local/bin` which is universally on PATH. In this case, `export_path=""` is redundant but safe — the `containerEnv.PATH` entry covers all container processes.

### Shell Initialization for nvm (Bare-Metal and Non-Container Use)

For `method=nvm`, the installer writes a shell initialization snippet to startup files (when `export_path=auto`). This snippet:
1. Exports `NVM_SYMLINK_CURRENT=true` (so nvm maintains the `current` symlink for all shells)
2. Exports `NVM_DIR` to the configured nvm directory
3. Sources `$NVM_DIR/nvm.sh` (activates the `nvm` shell function and sets `PATH` dynamically)
4. Sources `$NVM_DIR/bash_completion` (optional, enables nvm tab completion in bash)

This is the correct approach for nvm — it must NOT write a hardcoded versioned bin path (e.g. `$NVM_DIR/versions/node/v24.11.1/bin`) to shell startup files, because that path becomes stale as soon as `nvm use` switches to a different version. The `nvm.sh` sourcing approach is version-agnostic and always reflects the currently active version.

Files written to (system-wide, root install, `export_path=auto`):
- `/etc/profile.d/nvm_init.sh` — login shells (bash and sh)
- System-wide bashrc — non-login interactive bash
- `<zshdir>/zshenv` — all zsh sessions (login and non-login)
- BASH_ENV file registered in `/etc/environment` — non-interactive bash (Docker `RUN`, cron, CI)

Per-user writes (when `users` is specified): the same snippet is also written to each user's login file (`~/.bash_profile` or equivalent), `~/.bashrc`, `~/.zprofile`, and `~/.zshrc`. Note: `~/.zshenv` is intentionally excluded — it is sourced for all zsh processes including non-interactive scripts, and loading nvm there would affect build tools and CI scripts that use zsh non-interactively. `~/.zprofile` and `~/.zshrc` cover login and interactive zsh sessions respectively.

> **`method=binary` note:** When `method=binary`, nvm is not installed. The `NVM_DIR` and `NVM_SYMLINK_CURRENT` entries in `containerEnv` are still present in the container environment but are unused. The `current/bin` PATH entry points to a non-existent directory — this is harmless (non-existent directories in `PATH` are silently ignored).

### Troubleshooting

**`node: not found` in a Docker `RUN` step:**
- Ensure `export_path=auto` (the default) so that `/etc/environment` is written with a `BASH_ENV` pointing to a script that sources the PATH.
- Or use a `RUN` step that explicitly sources: `RUN . /usr/local/share/nvm/nvm.sh && node --version`.

**`method=binary` fails on Alpine:**
- The official Node.js binaries are glibc-only. Switch to `method=nvm` (the default).

**Long build times on Alpine:**
- Source compilation of Node.js takes ~10–20 minutes. This is expected and cannot be avoided when using nvm on Alpine. Consider caching the devcontainer build layer or using a base image with Node.js pre-installed.

**`nvm_dir` override with `symlink=false`:**
- If you set `nvm_dir` to a non-default path AND disable symlinks, remember to also set `containerEnv.NVM_DIR` and `containerEnv.PATH` in `devcontainer.json`. With `symlink=true` (the default), the installer creates `/usr/local/share/nvm → nvm_dir` automatically and no extra config is needed.

**Version resolution failure:**
- `method=binary` with `version=lts/*` queries `nodejs.org/dist/index.json`. If network access is restricted, provide an explicit version string (e.g. `"22.15.1"`) to skip the resolver.

**`node: not found` after `nvm use` in a Dockerfile `RUN` step:**
- `nvm use` updates `$NVM_DIR/current` but Docker `RUN` steps do not inherit environment from previous steps. Use: `RUN . $NVM_DIR/nvm.sh && nvm use 20 && node --version`.

**pnpm/yarn not found after install:**
- These are installed into the active nvm version's bin directory and linked via the `current/bin` PATH. Ensure the shell has sourced nvm (`$NVM_DIR/nvm.sh`) before using them in subsequent `RUN` steps.

**`nvm: command not found` in a new login shell:**
- The nvm init snippet was written to shell startup files by `export_path=auto`. If `export_path=""` was set, the snippet was skipped — nvm is only available in container processes with `containerEnv`. To fix on bare metal: re-run the installer with `export_path=auto`, or manually source `$NVM_DIR/nvm.sh` in your shell RC file.
- If the shell startup file is non-standard, set `export_path` to the explicit path(s) to write to.

**`additional_versions` is silently ignored:**
- `additional_versions` is only applicable for `method=nvm`. When `method=binary`, nvm is not used and multiple side-by-side Node.js versions are not supported. The installer emits a warning and skips. Use `method=nvm` to manage multiple versions.

**pnpm or yarn install fails / `node: command not found` during pnpm/yarn install:**
- Both `pnpm_version` and `yarn_version` are skipped when `version=none` (no Node.js was installed). Set a non-`none` version to install Node.js first.
- If using `method=nvm`, the installer must source nvm internally before running npm. If you see `npm not found`, check that `NODE_GYPDEPS` is not preventing nvm from loading (use `debug=true` to trace the issue).
