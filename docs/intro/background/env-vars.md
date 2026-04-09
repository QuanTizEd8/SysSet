# Environment Variables

Environment variables are named strings available to all applications,
providing a simple way to share configuration settings
between multiple applications and processes in Linux.
They are used to adapt applications' behavior to the environment they are running in.
The value of an environmental variable can for example be
the location of all executable files in the file system,
the default editor that should be used, or the system locale settings.
You can see each application's manual to see what variables are used by that application.

## How Environment Variables Work

Every process on Linux maintains its own **environment**: a set of key-value string
pairs. When a process creates a child process (via `fork`/`exec`), the child
**inherits a copy** of the parent's environment at that moment. Changes to the
child's environment do not affect the parent, and changes the parent makes
afterwards do not reach the child.

This inheritance model has a critical practical implication: environment variables
must be configured in a **parent process before it spawns the target process**.
There is no mechanism to inject new variables into an already-running process.
This is why we care which files are read, and when.

## Mechanisms for Setting Environment Variables

There is no single configuration file that works in all scenarios. The available
mechanisms differ by *who reads them*, *when*, and *under what conditions*.
Understanding this is essential for reliable environment setup in systems that
span multiple invocation contexts — interactive terminals, CI pipelines,
devcontainers, SSH, and automated agents.

### `/etc/environment` — System-Wide, Shell-Agnostic

`/etc/environment` is a plain key-value file read at **session initialization time**
by several distinct components:

- **PAM `pam_env` module**: For any PAM-authenticated session — SSH logins, TTY
  logins, display manager logins, `su`, and (when configured) `sudo`.
- **VS Code Remote server**: VS Code reads this file directly when spawning
  terminals in a container or on a remote machine, ensuring variables are available
  in all integrated terminals without requiring a PAM login flow
  (cf. [vscode-remote-release#6157](https://github.com/microsoft/vscode-remote-release/issues/6157)).
- **devcontainer CLI and compatible tooling**: Per the devcontainer spec, `ENV`
  Dockerfile instructions and `containerEnv` properties from `devcontainer.json`
  are written into this file when the container is started.

**Format:** Simple `KEY="value"` pairs, one per line. No `export` keyword.
Double quotes are supported (and recommended) for values containing spaces.

```ini
MY_VAR="hello world"
MY_OTHER_VAR=simple
```

**Critical limitation: variable expansion is not supported.**
Writing `PATH=$PATH:/new/path` stores the *literal string* `$PATH:/new/path`.
This is by design — the file is processed by a C library (PAM `pam_env`), not a
shell. Use `/etc/profile.d/` scripts for PATH additions that require expansion.

**Use for:** Static variables whose values are known at configuration time and
don't need to reference other variables — application flags, locale settings,
`BASH_ENV` (see below), and any variable that must be visible to non-shell
processes.

### `/etc/profile.d/*.sh` — Login Shells

Scripts with a `.sh` extension in `/etc/profile.d/` are sourced by `/etc/profile`
for all **login shells**. Because they are full shell scripts, they support
variable expansion, conditionals, and any shell logic.

```sh
# /etc/profile.d/myenv.sh
export MY_APP_HOME="/opt/myapp"
export PATH="$PATH:$MY_APP_HOME/bin"
```

Login shells occur in:
- SSH sessions
- TTY / console logins
- `su -l` / `sudo -i`
- Bash invoked with `bash -l` or `bash --login`
- Zsh login shells (macOS Terminal.app defaults to login shells)

Do **not** edit `/etc/profile` directly on Debian-based systems — it is owned by
the `base-files` package. Add scripts to `/etc/profile.d/` instead.

### `BASH_ENV` — Non-Login Non-Interactive Bash

When bash is invoked in **non-login, non-interactive** mode — the default in CI
pipelines, container lifecycle hooks, `docker exec`, GitHub Actions `run` steps,
and devcontainer CLI `exec` commands — it sources *neither* `/etc/profile` nor
`bash.bashrc`. Instead, it checks the `BASH_ENV` variable and, if set, sources
the file it points to before executing the script.

Setting `BASH_ENV` in `/etc/environment` causes VS Code, devcontainer tools, and
other launchers to inject it into the process environment. Any non-interactive
bash subprocess then automatically sources the target file:

```ini
# /etc/environment
BASH_ENV=/etc/bash/bash_env
```

```sh
# /etc/bash/bash_env  (keep this free of interactive-only code)
export PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin"
export EDITOR=nano
```

**Caveats:**
- `BASH_ENV` is honored only by **bash**, not by `sh`, `dash`, or other shells.
- `BASH_ENV` is **not** processed when bash is interactive, so there is no
  double-sourcing risk between interactive and non-interactive sessions.
- Keep the `BASH_ENV` target lean: no output, no TTY assumptions, no
  interactive features.

### `/etc/zsh/zshenv` — All Zsh Invocations

`/etc/zsh/zshenv` (or `/etc/zshenv` on Red Hat distributions and macOS) is the
single Zsh configuration file sourced on **every Zsh invocation**, regardless of
login or interactive status. This makes it the natural place to source the same
environment setup file used for bash:

```zsh
# /etc/zsh/zshenv
emulate sh -c 'source "/etc/bash/bash_env"'
```

The `emulate sh` wrapper evaluates the sourced script in POSIX-compatible mode,
preventing Zsh-specific syntax differences from causing errors in a script written
for `sh`/bash.

**Keep this file minimal.** It runs for every Zsh invocation — including
non-interactive scripts — so it must never produce output or assume a TTY.

### `/etc/environment.d/` — systemd User Services Only

Files in `/etc/environment.d/` (and `~/.config/environment.d/`) share the same
`KEY=value` syntax as `/etc/environment` but are processed by
**`systemd-environment-d-generator`** — a completely different mechanism from PAM.
They make variables available to the **systemd user service manager**
(`systemd --user`) and its activated services only.

**NOT read by:**
- PAM (`pam_env`)
- SSH or TTY login sessions
- Interactive or non-interactive shells directly
- VS Code remote server
- devcontainer CLI or GitHub Actions

**Only read by:**
- KDE Plasma applications on Wayland (which run as systemd user services)
- Other services managed by `systemd --user`

Since containers — including devcontainers — typically do not run a
`systemd --user` instance, files in `/etc/environment.d/` have **no effect** in
container environments and must not be used for devcontainer variable configuration.

---

## Environment Variables in Devcontainers

### How Variables Enter the Container

| Source | Mechanism | Where it lands |
|---|---|---|
| `ENV` in `Dockerfile` | Written to `/etc/environment` by VS Code / devcontainer CLI at container start | All processes in container |
| `containerEnv` in `devcontainer.json` | Written to `/etc/environment` by VS Code / devcontainer CLI | All processes in container |
| `remoteEnv` in `devcontainer.json` | Injected by devcontainer client into its process env (not written to `/etc/environment`) | Client-managed processes: VS Code terminals, lifecycle hooks, `devcontainer exec`; NOT bare `docker exec` or raw SSH |
| Base image `/etc/environment` | Present from the image build; read by PAM and VS Code | All processes |

For example, given a `devcontainer.json`:

```json
{
    "name": "example",
    "build": {
        "dockerfile": "Dockerfile"
    },
    "containerEnv": {
        "MY_CONTAINER_VAR": "hello",
        "MY_CONTAINER_VAR2": "hello container var"
    }
}
```

and a `Dockerfile`:

```Dockerfile
FROM debian:latest
ENV MY_DOCKER_VAR=hello
ENV MY_DOCKER_VAR2="hello world"
```

The resulting `/etc/environment` inside the running devcontainer will contain:

```ini
MY_CONTAINER_VAR="hello"
MY_CONTAINER_VAR2="hello container var"
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
MY_DOCKER_VAR="hello"
MY_DOCKER_VAR2="hello world"
```

### `containerEnv` vs `remoteEnv`

- **`containerEnv`**: Written to `/etc/environment`. Available to *all* processes
  in the container — terminals, lifecycle hooks, devcontainer CLI `exec`, GitHub
  Actions, AI coding agents. Use this for variables that tooling needs everywhere.
- **`remoteEnv`**: Injected by the devcontainer client (VS Code, devcontainer CLI)
  into its own process and all processes it spawns — integrated terminals,
  extensions, lifecycle hooks (`postCreateCommand`, `postStartCommand`, etc.), and
  `devcontainer exec` commands. It is *not* written to `/etc/environment`, so it is
  unavailable to processes started outside the devcontainer client (bare
  `docker exec`, raw SSH). Values can reference container variables via
  `${containerEnv:VAR}` and are updated without rebuilding the container.

### `userEnvProbe`

The `userEnvProbe` property in `devcontainer.json` controls which shell type the
devcontainer implementation uses to **probe** the user's environment: it runs
`printenv` inside that shell to capture variables from startup files (`.profile`,
`.bashrc`, etc.) and injects them into the server process. Supported values:

| Value | Shell invoked for probing |
|---|---|
| `"none"` | No probing; only `containerEnv`/`ENV` variables available |
| `"loginShell"` | `sh -l` (sources `/etc/profile`, `~/.profile`) |
| `"loginInteractiveShell"` **(default)** | `sh -l -i` (sources profile and interactive rc files) |
| `"interactiveShell"` | `sh -i` (sources interactive rc files) |

**Important limitation:** `userEnvProbe` determines which shell type is used for
the *probe* only. It does **not** change the shell invocation type used for the
VS Code integrated terminal. The VS Code integrated terminal is always a
non-login, interactive shell started directly by VS Code's node process. The
terminal shell type can be configured independently via
`terminal.integrated.profiles` in VS Code settings.

### Shell Invocations Across Devcontainer Clients

Different tools that run code inside a devcontainer use different shell invocations,
which determines which configuration files are sourced:

| Client | Invocation | Config files sourced |
|---|---|---|
| VS Code integrated terminal | Non-login, interactive | `/etc/environment` (VS Code), then `zshenv`/`zshrc` (zsh) or `bash.bashrc` (bash) |
| devcontainer CLI `exec` | Non-login, non-interactive | `/etc/environment` (inherited) + `$BASH_ENV` (bash only) |
| GitHub Actions (`devcontainer/ci`) | Non-login, non-interactive | `/etc/environment` (inherited) + `$BASH_ENV` (bash only) |
| GitHub Copilot coding agent | Non-login, non-interactive | Same as devcontainer CLI |
| SSH into container | Login, interactive | PAM → `/etc/environment` → `/etc/profile` → `/etc/profile.d/` |
| `docker exec` directly | Non-login, non-interactive | Only inherited OS env (no rc files) |
| `RUN` in `Dockerfile` | Non-login, non-interactive | Only Docker image env (use `SHELL ["/bin/bash", "-l", "-c"]` for login shell) |

---

## Recommended Setup for All Scenarios

To reliably cover all the above clients and invocation types in a devcontainer or
any Debian/Ubuntu-based Linux system, use this layered approach:

**1. `/etc/environment` — Static variables and bootstrapping:**

```ini
# Static values only — no variable expansion
EDITOR=nano
PAGER=less
# Wire up non-interactive bash to source the dynamic env file
BASH_ENV=/etc/bash/bash_env
```

**2. `/etc/bash/bash_env` — Dynamic variables and PATH:**

```sh
# Sourced by:
#   - login bash          (via /etc/profile → profile.d, or directly)
#   - non-interactive bash (via $BASH_ENV)
#   - all zsh              (via /etc/zsh/zshenv)
extend_path --prepend "$HOME/.local/bin" "$HOME/bin"
extend_path --append "/opt/myapp/bin"
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CACHE_HOME="${HOME}/.cache"
export XDG_STATE_HOME="${HOME}/.local/state"
```

**3. `/etc/zsh/zshenv` — All Zsh invocations:**

```zsh
emulate sh -c 'source "/etc/bash/bash_env"'
```

**4. `/etc/profile.d/env.sh` — Login shells of any Bourne-compatible shell:**

```sh
# Same PATH additions for any login shell (bash, sh, dash, ksh, zsh via zprofile)
export PATH="$PATH:/opt/myapp/bin"
```

This setup ensures:

| Scenario | PATH / vars available |
|---|---|
| VS Code terminal (zsh) | `/etc/environment` + `bash_env` (via `zshenv`) |
| VS Code terminal (bash) | `/etc/environment` + `bash.bashrc` |
| devcontainer CLI / GHA / Copilot | `/etc/environment` + `bash_env` (via `$BASH_ENV`) |
| SSH login (bash/zsh) | PAM (`/etc/environment`) + `/etc/profile` + `/etc/profile.d/` |
| Non-interactive bash | `/etc/environment` + `bash_env` (via `$BASH_ENV`) |
| All zsh | `/etc/environment` + `bash_env` (via `zshenv`) |

---

## XDG Base Directories

The [XDG Base Directory Specification](https://wiki.archlinux.org/title/XDG_Base_Directory)
defines standard locations for user-specific application data. Applications that
conform to it use these environment variables to locate files:

| Variable | Default | Purpose |
|---|---|---|
| `XDG_CONFIG_HOME` | `$HOME/.config` | User-local configuration files |
| `XDG_DATA_HOME` | `$HOME/.local/share` | User-local data files |
| `XDG_CACHE_HOME` | `$HOME/.cache` | Non-essential cached data (safe to delete) |
| `XDG_STATE_HOME` | `$HOME/.local/state` | Persistent state: logs, history files |
| `XDG_RUNTIME_DIR` | `/run/user/<uid>` | Runtime sockets and PIDs (short-lived) |

Setting these variables early in the environment (e.g., in `/etc/bash/bash_env`)
ensures all applications use consistent, predictable locations regardless of how
the shell was invoked.

For reference, see [XDG Base Directory support in common applications](https://wiki.archlinux.org/title/XDG_Base_Directory#Support).

## References

- [Linux man page: environment(5)](https://man7.org/linux/man-pages/man5/environment.5.html)
- [Linux man page: environment.d(5)](https://man7.org/linux/man-pages/man5/environment.d.5.html)
- [Debian man page: environment.d(5)](https://manpages.debian.org/experimental/systemd/environment.d.5.en.html)
- [Arch Wiki: Environment variables](https://wiki.archlinux.org/title/Environment_variables)
- [Debian Wiki: EnvironmentVariables](https://wiki.debian.org/EnvironmentVariables)
- [Ubuntu Community: EnvironmentVariables](https://help.ubuntu.com/community/EnvironmentVariables)
- [VS Code: ENV/containerEnv written to /etc/environment](https://github.com/microsoft/vscode-remote-release/issues/6157)
- [devcontainer.json reference — general properties](https://containers.dev/implementors/json_reference/#general-properties)
- [superuser: /etc/environment vs /etc/profile](https://superuser.com/questions/664169/what-is-the-difference-between-etc-environment-and-etc-profile)
- [askubuntu: PATH in /etc/environment vs /etc/profile](https://askubuntu.com/questions/866161/setting-path-variable-in-etc-environment-vs-profile)
- [Arch Wiki: XDG Base Directory](https://wiki.archlinux.org/title/XDG_Base_Directory)
