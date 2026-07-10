# Notes

## Conflict resolution

Before creating the user or group, the script compares the requested
UID/GID against existing accounts:

| Situation | `replace_existing=true` | `replace_existing=false` |
|---|---|---|
| UID/GID already correct | No-op — account reused as-is | Same |
| Username exists with wrong UID | Removes old account first | Error |
| UID in use by a different user | Removes that user first | Error |
| Group name exists with wrong GID | Removes old group first | Error |
| GID in use by a different group | Removes that group and its members | Error |

Home directories are **never** removed, regardless of `replace_existing`.

## Sudo drop-in

When `sudo_access` is enabled, a file is written to `<sudoers_dir>/<username>`
with the content:

```
<username> ALL=(ALL) NOPASSWD:ALL
```

The file is created with mode `0440` and validated with `visudo` before being
moved into place; a validation failure removes the file and aborts.
