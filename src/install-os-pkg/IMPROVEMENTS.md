# Improvement Opportunities for `install-os-pkg`

## 1. `--- key` section type for repository signing keys

**What:** Add a fourth manifest section type `key` that imports a GPG/signing
key before any `repo` section is processed.

**Why:** Third-party repositories require a trusted key to be imported first
— this is currently handled in a `prescript` section, which works but is
unstructured and easy to get wrong. A dedicated `key` section would be:

```
--- key [pm=apt]
https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key /usr/share/keyrings/nodesource.gpg

--- repo [pm=apt]
deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main

--- pkg [pm=apt]
nodejs
```

The format `<url> <destination-path>` is unambiguous and lets the script fetch
the key with `curl`, convert it with `gpg --dearmor`, and place it in one
deterministic step — eliminating the common footgun of forgetting `--dearmor`
or writing to the wrong path.

---

## 2. `--dry-run` flag

**What:** A flag (or option `dry_run`) that prints what would be installed
without executing any package manager commands or shell scripts.

**Why:** Useful for auditing manifests in CI, reviewing what a feature will
install before merging, or debugging selector logic. Output would look like:

```
[dry-run] prescript: 3 lines — would execute
[dry-run] repo: 1 entry — would add to /etc/apt/sources.list.d/syspkg-installer.list
[dry-run] packages (4): git curl jq ripgrep
[dry-run] script: 2 lines — would execute
```

---

## 3. `version` selectors in `/etc/os-release`

**What:** The selector system already reads all `/etc/os-release` keys; the
fields `version_id` and `version_codename` are already in the `OS_RELEASE`
map and mentioned in the debug log. But they are not documented or tested.

**Pitch:** Document them explicitly with examples and add a test scenario that
exercises them:

```
--- pkg [version_codename=bookworm]
some-bookworm-only-package
```

This costs nothing to implement (the infrastructure is already there) and
unlocks a common real-world use case: pinning a package to a specific Debian
or Ubuntu release.

---

## 4. Automatic update-skip when package lists were refreshed recently

**What:** When `no_update` is `false` (the default) but the package lists were
refreshed within the last N minutes by a previous step in the same build
layer, skip the update.

**Why:** Multi-feature devcontainer builds often trigger `apt-get update`
multiple times in short succession, wasting network time. A heuristic based
on the mtime of `/var/lib/apt/lists/partial` or a lock timestamp would
eliminate redundant refreshes automatically.

**Implementation sketch:**
```bash
_APT_LISTS_AGE=$(( $(date +%s) - $(stat -c %Y /var/lib/apt/lists 2>/dev/null || echo 0) ))
if [[ $_APT_LISTS_AGE -lt 300 ]]; then
    echo "ℹ️  Package lists refreshed ${_APT_LISTS_AGE}s ago — skipping update." >&2
    # skip UPDATE step
fi
```

---

## 5. Multiple manifest inputs

**What:** Allow `--manifest` to be specified more than once (CLI) or accept a
space/newline-delimited list of files (feature option).

**Why:** In a complex project it is natural to split packages into files by
concern (`packages-base.txt`, `packages-dev.txt`, `packages-ci.txt`) and
compose them. Currently the only workaround is to concatenate files in a
`prescript`, which is awkward.

**Design:** Manifests would be parsed in order and their sections merged.
Inline manifest content would remain single-value (inline is already a
workaround for lists).
