---
description: "Use when writing or editing ospkg manifest files (dependencies/base.txt, dependencies/sudo.txt). Covers the package list syntax, per-package-manager selectors, OS-release selectors, and script blocks."
applyTo: "src/**/dependencies/*.txt"
---

# ospkg Manifest Format

Manifests are consumed by `ospkg::run --manifest <file>`.
Each non-blank, non-comment line is a package to install, optionally filtered by selectors.

## Basic Syntax

```
# comment
pkg1                           # unconditional package
pkg2    [pm=apt]               # only on apt systems
pkg3    [pm=apk,dnf]           # on apk or dnf (OR between values)
pkg4    [pm=apt] [id=ubuntu]   # apt AND Ubuntu (AND between selectors)
```

## Selectors

| Selector | Matches |
|----------|---------|
| `[pm=<mgr>]` | Package manager: `apt`, `apk`, `dnf`, `pacman`, `zypper` |
| `[id=<dist>]` | OS ID from `/etc/os-release`: `ubuntu`, `debian`, `alpine`, `fedora` |
| `[version_id=<ver>]` | OS version: `22.04`, `3.18`, etc. |
| `[id_like=<family>]` | OS family: `debian`, `rhel` |

Multiple selectors on the same line are ANDed. Multiple comma-separated values inside one selector are ORed.

## Script Blocks

Execute arbitrary shell code for a specific package manager, after all packages are installed:

```
--- script [pm=apt]
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
---
```

- The `--- script` line opens the block; a bare `---` or the end of file closes it.
- Multiple `--- script` blocks are allowed.
- The block runs in a subshell with `set -e`.

## Naming Conventions

| File | Purpose |
|------|---------|
| `dependencies/base.txt` | Packages installed unconditionally before the feature's main logic |
| `dependencies/sudo.txt` | Packages installed via sudo (used by `setup-user`) |

## `ospkg::run` Flags Reference

| Flag | Effect |
|------|--------|
| `--manifest <file>` | Read packages from file |
| `--check_installed` | Skip packages that are already installed (idempotent) |
| `--no_update` | Skip `ospkg::update` (don't refresh indexes) |
| `--no_clean` | Skip cache cleanup after install |
| `--dry_run` | Print resolved packages without installing |

## Further Reading

- `docs/ref/install-os-pkg.md` — full `install-os-pkg` feature reference (and its `ospkg` library backend)
