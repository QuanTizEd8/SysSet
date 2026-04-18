## Usage

### Basic

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/setup-user:0": {}
  }
}
```

With the defaults above, the feature creates:

- User **`vscode`** (UID `1000`) with primary group **`vscode`** (GID `1000`)
- Home directory **`/home/vscode`** owned by the user
- Login shell **`/bin/bash`**
- Passwordless **`sudo`** via `/etc/sudoers.d/vscode`

### Custom username and IDs

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/setup-user:0": {
      "username": "devuser",
      "user_id": "2000",
      "group_id": "2000",
      "group_name": "devgroup"
    }
  }
}
```

### Custom home directory and shell

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/setup-user:0": {
      "home_dir": "/workspaces/myapp",
      "user_shell": "/bin/zsh"
    }
  }
}
```

### No sudo, add supplementary groups

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/setup-user:0": {
      "sudo_access": false,
      "extra_groups": "docker,dialout"
    }
  }
}
```

> **Note** Groups listed in `extra_groups` must already exist in the image.
> Create them in your `Dockerfile` or via another feature before this one runs.

---

## How it works

### Bootstrap

The top-level `install.sh` is a minimal POSIX `sh` script. It uses the
[`install-os-pkg`](../install-os-pkg/) feature (declared as a `dependsOn`
dependency) to install base requirements — `bash` and, on Alpine, `shadow`
(the `useradd`/`groupadd` suite) — before handing control to
`install.bash` via `exec bash`.

This two-stage design avoids the "bootstrap paradox" of calling `bash`
before it is installed.

### Conflict resolution

Before creating the user or group, the script compares the requested
UID/GID against existing accounts:

| Situation | `replace_existing=true` | `replace_existing=false` |
|---|---|---|
| UID/GID already correct | No-op — account reused as-is | Same |
| Username exists with wrong UID | Removes old account first | Error |
| UID in use by a different user | Removes that user first | Error |
| Group name exists with wrong GID | Removes old group first | Error |
| GID in use by a different group | Removes that group + its members | Error |

Home directories are **never** removed, regardless of `replace_existing`.

### Home directory

Created with `mkdir -p` and seeded from `/etc/skel`. If the directory
already exists, only ownership is corrected; existing contents are untouched.

### Sudo drop-in

A file is written to `<sudoers_dir>/<username>` with the content:

```
<username> ALL=(ALL) NOPASSWD:ALL
```

The file is created with mode `0440`. If `visudo` is available it is used to
validate the file before finalising; a validation failure removes the file
and aborts.
