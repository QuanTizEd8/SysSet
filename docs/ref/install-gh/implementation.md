# Implementation Reference — install-gh

The installer follows the established pattern of a thin orchestrator script (`scripts/install.sh`) that
dispatches to feature-local helper functions. All low-level primitives (platform detection, package management,
HTTP fetches, checksum verification, shell directory detection, user resolution) come from `lib/`. No new
library functions are required.

---

## Building Blocks

### `os__platform` · `os__id` · `os__id_like` · `os__arch` · `os__kernel`
- **Reuse** from `lib/os.sh`.
- `os__platform` → `debian|alpine|rhel|macos`; `os__id` → raw `/etc/os-release` `ID` field.
- `os__id` is used for Arch Linux detection (ID=`arch`) since `os__platform` maps Arch → `debian` as the
  fallback and would route incorrectly.

### `ospkg__detect` · `ospkg__run` · `ospkg__install` · `ospkg__update`
- **Reuse** from `lib/ospkg.sh`.
- `ospkg__detect` is called for the repos method to initialise package manager state; `ospkg__install`
  (or `ospkg__run --manifest`) installs individual packages.

### `github__latest_tag`
- **Reuse** from `lib/github.sh`.
- Used by `_gh__resolve_version` to translate `version=latest` → `v2.89.0` → strips the `v` prefix.

### `net__fetch_url_file`
- **Reuse** from `lib/net.sh`.
- Used by `_gh__install_binary` to download the release archive and checksums file.

### `checksum__verify_sha256`
- **Reuse** from `lib/checksum.sh`.
- The `gh_<ver>_checksums.txt` file is a multi-asset file; the caller extracts the expected hash with `grep`
  and passes it to `checksum__verify_sha256 <archive> <hash>`.

### `shell__detect_zshdir`
- **Reuse** from `lib/shell.sh`.
- Used by `_gh__install_completions` to locate the system-wide zsh directory for zsh completion install.

### `users__resolve_list`
- **Reuse** from `lib/users.sh`.
- Used by `_gh__install_extensions` to expand `users` option tokens (`_REMOTE_USER`, `_CONTAINER_USER`,
  `all`) into a deduplicated list of usernames.

---

## Feature-Local Helper Functions

All the following live in `scripts/install.sh` and are named with the `_gh__` prefix.

### `_gh__resolve_version`
**Responsibility:** Resolve `VERSION` to a concrete semver string (no `v` prefix, e.g. `2.89.0`).
- If `VERSION=latest`: call `github__latest_tag "cli/cli"`, strip leading `v`.
- Otherwise: use `VERSION` as-is (no validation — invalid versions will fail at download time).
- Prints the resolved version to stdout.

### `_gh__check_existing`
**Responsibility:** Detect whether `gh` is already installed and act on `IF_EXISTS`.
- `command -v gh` to check presence.
- If found and `IF_EXISTS=skip`: log notice and `exit 0`.
- If found and `IF_EXISTS=fail`: log error and `exit 1`.
- If found and the installed version string matches the resolved target version: always `exit 0` (idempotent),
  regardless of `IF_EXISTS`.
- Version comparison: `gh --version` → first line → extract semver with a sed pattern.

### `_gh__install_repos`
**Responsibility:** Dispatch to the correct platform-specific repos installer.

Detection order:
1. `os__id` = `arch` or `os__id_like` contains `arch` (or `manjaro`) → `_gh__repos_arch`
2. `os__platform` = `alpine` → `_gh__repos_alpine`
3. `os__platform` = `debian` → `_gh__repos_debian`
4. `os__platform` = `rhel` → `_gh__repos_rhel`
5. `os__platform` = `macos` → `_gh__repos_macos`
6. Else: unsupported, `exit 1` with message.

### `_gh__repos_debian`
**Responsibility:** Set up the official GitHub CLI apt repo and install `gh`.
1. Install prerequisites: `ospkg__install gnupg curl` (gpg may be absent on minimal images).
2. Download and install GPG keyring:
   ```bash
   mkdir -p /etc/apt/keyrings
   net__fetch_url_file \
     "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
     "/etc/apt/keyrings/githubcli-archive-keyring.gpg"
   chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
   ```
3. Add apt source list:
   ```bash
   local _arch; _arch="$(dpkg --print-architecture)"
   cat > /etc/apt/sources.list.d/github-cli.list << EOF
   deb [arch=${_arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main
   EOF
   ```
4. `ospkg__update --force`; then install:
   - `VERSION=latest` → `ospkg__install gh`
   - specific version → `ospkg__install "gh=${VERSION}"`

### `_gh__repos_rhel`
**Responsibility:** Set up the official GitHub CLI rpm repo and install `gh`.
1. Detect sub-PM and add the repo:
   - `command -v zypper`: `zypper addrepo https://cli.github.com/packages/rpm/gh-cli.repo gh-cli && zypper ref gh-cli`
     (writes to `/etc/zypp/repos.d/` — zypper's native location; do **not** use `/etc/yum.repos.d/` for zypper)
   - `command -v dnf` or `command -v yum`:
     ```bash
     mkdir -p /etc/yum.repos.d
     net__fetch_url_file \
       "https://cli.github.com/packages/rpm/gh-cli.repo" \
       "/etc/yum.repos.d/gh-cli.repo"
     ```
2. Detect sub-PM and install:
   - `command -v zypper`: `zypper install -y gh`
   - `command -v dnf` → detect dnf major version ≥ 5 = dnf5, < 5 = dnf4:
     ```bash
     local _major; _major="$(dnf --version 2>/dev/null | head -1 | grep -oE '^[0-9]+')"
     ```
     Both dnf4 and dnf5: `dnf install -y gh --repo gh-cli` (the `--repo` flag is the same for both,
     the config-manager step is skipped since we copied the repo file directly)
   - `command -v yum`: `yum install -y gh`
3. Version pinning is not supported via rpm; a warning is logged when `VERSION ≠ latest`.

**Note:** Downloading the `.repo` file directly to `/etc/yum.repos.d/` bypasses the need for
`dnf config-manager` (which requires a plugin), giving a simpler cross-variant flow.

### `_gh__repos_alpine`
**Responsibility:** Install `github-cli` via apk.
1. If `VERSION ≠ latest`, log a warning: version pinning is not supported via apk.
2. `ospkg__install github-cli`

### `_gh__repos_arch`
**Responsibility:** Install `github-cli` via pacman.
1. If `VERSION ≠ latest`, log a warning: version pinning is not supported via pacman.
2. `ospkg__update` then `ospkg__install github-cli`

### `_gh__repos_macos`
**Responsibility:** Install `gh` via Homebrew.
1. `VERSION=latest` → `ospkg__install gh`
2. Specific version: log a warning that Homebrew has no versioned formula for `gh`. Install `gh` (latest)
   and advise using `method=binary` for version pinning.

### `_gh__install_binary`
**Responsibility:** Download, verify, and install the `gh` binary from GitHub Releases.
Accepts the resolved version string as `$1` (already resolved by the orchestrator at step 8; does **not** call `_gh__resolve_version` again).
1. Determine asset name:
   - Kernel (`os__kernel`): `Linux` → `os=linux`, `Darwin` → `os=macOS`
   - Architecture (`os__arch`): map `uname -m` → asset arch
     - `x86_64` → `amd64`; `aarch64|arm64` → `arm64`; `i386|i686` → `386`; `armv6l|armv7l` → `armv6`
   - Extension: Linux → `tar.gz`, macOS → `zip`
   - Archive name: `gh_${VERSION}_${os}_${arch}.${ext}`
   - Archive dir inside: `gh_${VERSION}_${os}_${arch}` (due to `wrap_in_directory: true` in goreleaser)
3. Download to `INSTALLER_DIR`:
   ```bash
   mkdir -p "${INSTALLER_DIR}"
   _url_base="https://github.com/cli/cli/releases/download/v${VERSION}"
   net__fetch_url_file "${_url_base}/${_archive_name}" "${INSTALLER_DIR}/${_archive_name}"
   net__fetch_url_file "${_url_base}/gh_${VERSION}_checksums.txt" "${INSTALLER_DIR}/checksums.txt"
   ```
4. Extract expected SHA-256 from checksums.txt:
   ```bash
   _expected="$(grep "${_archive_name}" "${INSTALLER_DIR}/checksums.txt" | awk '{print $1}')"
   ```
5. Verify: `checksum__verify_sha256 "${INSTALLER_DIR}/${_archive_name}" "${_expected}"`; exit 1 on mismatch.
6. Extract archive:
   - Linux: `tar -xzf ... -C "${INSTALLER_DIR}"`
   - macOS: `unzip -q ... -d "${INSTALLER_DIR}"`
7. Install binary:
   ```bash
   mkdir -p "${INSTALL_PATH}"
   install -m 755 "${INSTALLER_DIR}/${_archive_dir}/bin/gh" "${INSTALL_PATH}/gh"
   ```
8. If `INSTALL_COMPLETIONS=true`, call `_gh__install_completions --from-archive "${INSTALLER_DIR}/${_archive_dir}"`.
9. If `NO_CLEAN ≠ true`, `rm -rf "${INSTALLER_DIR}"`.
10. Verify: `"${INSTALL_PATH}/gh" --version`.

### `_gh__create_symlink`
**Responsibility:** Create `/usr/local/bin/gh -> INSTALL_PATH/gh` when `method=binary` and
`INSTALL_PATH ≠ /usr/local/bin`.
- No-op conditions: `SYMLINK ≠ true`, `METHOD=repos`, `INSTALL_PATH=/usr/local/bin`, or running as
  non-root (cannot write to `/usr/local/bin`).
- If `/usr/local/bin/gh` already exists as a real file (not a symlink), log an error and exit 1.
- If it exists as a symlink, remove it first, then re-link.
- `ln -sf "${INSTALL_PATH}/gh" /usr/local/bin/gh`
- This is the same pattern as `install-git`'s `symlink` option.

### `_gh__install_completions`
**Responsibility:** Install bash and zsh completions for any method.
- Called after gh is installed, regardless of method.
- For `method=binary`: input `$1` = extracted archive directory; reads completion files from
  `share/bash-completion/completions/gh` and `share/zsh/site-functions/_gh`.
- For `method=repos`: no archive dir; runs `gh completion -s bash` and `gh completion -s zsh` to
  generate completion content on the fly.
- Destination logic (same for both):
  - As root: bash → `/etc/bash_completion.d/gh`; zsh → `<zshdir>/completions/_gh` (via `shell__detect_zshdir`)
  - As non-root: bash → `$HOME/.local/share/bash-completion/completions/gh`; zsh → `$HOME/.zfunc/_gh`

### `_gh__install_extensions`
**Responsibility:** Install one or more gh CLI extensions for all resolved users.
1. Split `EXTENSIONS` on `,` into an array. Each entry is passed verbatim to `gh extension install`
   (accepts owner/repo slugs, full https:// URLs, or local paths).
2. Call `users__resolve_list` with the four env vars (`ADD_CURRENT_USER_CONFIG`,
   `ADD_REMOTE_USER_CONFIG`, `ADD_CONTAINER_USER_CONFIG`, `ADD_USER_CONFIG`) populated from
   the corresponding feature options (`add_current_user_config`, `add_remote_user_config`,
   `add_container_user_config`, `add_user_config`). These same env vars are also used by
   `_gh__configure_user`; both functions share the same resolved user set.
3. `users__resolve_list` auto-deduplicates; root is excluded from auto-detected paths when other
   non-root users are present.
4. For each user, for each extension:
   - As root: `su -l <user> -c "gh extension install <ext>"`
   - As non-root: run directly (restricted to current user by `users__resolve_list`)
5. Errors are logged as warnings (non-fatal) — one failed extension should not abort the install.

### `_gh__configure_user`
**Responsibility:** Apply per-user post-install configuration (`git_protocol`, `setup_git`,
`sign_commits`) for all resolved users.
1. Call `users__resolve_list` (same env var population as `_gh__install_extensions`).
2. If user list is empty, this function is a no-op.
3. For each user:
   a. If `GIT_PROTOCOL ≠ ""`: run `gh config set git_protocol "${GIT_PROTOCOL}"` as that user.
      - As root: `su -l <user> -c "gh config set git_protocol ${GIT_PROTOCOL}"`
      - As non-root: run directly.
      - This writes to `~/.config/gh/config.yml` (auto-created by gh on first write).
   b. If `SETUP_GIT=true`: run `gh auth setup-git --force --hostname "${GIT_HOSTNAME}"` as that user.
      - `--force` is required to succeed at build time without an active login.
      - Writes two entries to `~/.gitconfig` (via `git config --global`): an empty helper to sever
        any existing chain, then `credential."https://<hostname>".helper = !gh auth git-credential`.
   c. If `SIGN_COMMITS ≠ ""`: run as that user:
      - `ssh`: `git config --global gpg.format ssh` + `git config --global commit.gpgsign true`
      - `gpg`: `git config --global --unset-all gpg.format || true`
               (exit code 5 when the key doesn't exist; `|| true` prevents aborting under `set -e`) +
               `git config --global commit.gpgsign true`
      - In both cases, `user.signingkey` is not written (user-specific, unknown at build time).
4. Called even when `extensions` is empty (config steps are independent of extension installation).
5. Skip the function entirely if all three of `GIT_PROTOCOL`, `SETUP_GIT`, and `SIGN_COMMITS` are
   at their defaults (empty, false, empty).

---

## Details

### Step-by-Step Orchestration in `install.sh`

```
1.  Source libs: ospkg.sh → logging.sh → github.sh → checksum.sh → shell.sh → users.sh
2.  logging__setup + trap EXIT logging__cleanup
3.  Dual-mode argument parsing (env vars vs --flags)
4.  Apply defaults: VERSION=latest, METHOD=repos, INSTALL_PATH=/usr/local/bin,
    SYMLINK=true, INSTALL_COMPLETIONS=true, IF_EXISTS=skip, INSTALLER_DIR=/tmp/gh-install,
    NO_CLEAN=false, EXTENSIONS="", GIT_PROTOCOL="", SETUP_GIT=false, SIGN_COMMITS="",
    GIT_HOSTNAME=github.com, ADD_CURRENT_USER_CONFIG=true, ADD_REMOTE_USER_CONFIG=true,
    ADD_CONTAINER_USER_CONFIG=true, ADD_USER_CONFIG=""
5.  [[ DEBUG == true ]] && set -x
6.  os__require_root  (must run as root)
7.  EARLY-EXIT (no-mutation): if VERSION=latest AND gh is already in PATH:
      if IF_EXISTS=skip:  print info, exit 0  (no deps installed, no API call)
      if IF_EXISTS=fail:  print error, exit 1 (no deps installed, no API call)
    This preserves the contract that skip/fail make no system changes when the tool is
    already present and the caller did not request a specific version.
8.  ospkg__run --manifest base.yaml --check_installed  (install curl, ca-certificates)
9.  _resolved_version="$(_gh__resolve_version)"
10. Export user config env vars:
      ADD_CURRENT_USER_CONFIG, ADD_REMOTE_USER_CONFIG,
      ADD_CONTAINER_USER_CONFIG, ADD_USER_CONFIG
      (from the corresponding feature options, so users__resolve_list picks them up)
11. _gh__check_existing "$_resolved_version"  (handles version-pinned case: may exit 0 or 1
      based on IF_EXISTS, or always exit 0 when installed version matches target)
12. if METHOD=repos:
      _gh__install_repos
    elif METHOD=binary:
      _gh__install_binary "$_resolved_version"
13. _gh__create_symlink  (no-op when method=repos or install_path=/usr/local/bin)
14. if INSTALL_COMPLETIONS=true:
      if METHOD=binary:  (already called inside _gh__install_binary — no duplicate call needed)
        # completions handled inside _gh__install_binary via --from-archive
      elif METHOD=repos:
        _gh__install_completions --from-command
15. if GIT_PROTOCOL non-empty OR SETUP_GIT=true OR SIGN_COMMITS non-empty:
      _gh__configure_user
16. if EXTENSIONS non-empty:
      _gh__install_extensions
17. log success
```

### Arch Detection

Arch Linux has `ID=arch` in `/etc/os-release` and an empty `ID_LIKE`. `os__platform` maps unrecognised
IDs → `debian` (the fallback), which would incorrectly route Arch to `_gh__repos_debian` and fail. To
prevent this, the detection order in `_gh__install_repos` checks `os__id == arch` (or `os__id_like` contains
`arch` for Manjaro) explicitly, before falling through to `os__platform`.

### Version Pinning Constraints

| Platform / PM | `method=repos` pinning | `method=binary` pinning |
|---|---|---|
| Debian / Ubuntu | `gh=<version>` (apt) | Exact tarball download |
| RHEL / Fedora / Amazon Linux / SUSE | Not supported (warning logged) | Exact tarball download |
| Alpine | Not supported (warning logged) | Exact tarball download |
| Arch | Not supported (warning logged) | Exact tarball download |
| macOS | Not supported via Homebrew (warning logged) | Exact zip download |

### Binary Archive Inner Directory Structure

From `.goreleaser.yml` (`wrap_in_directory: true`):
```
gh_<version>_linux_<arch>/
  bin/gh
  share/bash-completion/completions/gh
  share/zsh/site-functions/_gh
  share/fish/vendor_completions.d/gh.fish
  share/man/man1/gh*.1
  LICENSE
```
macOS (zip) uses the same structure with `macOS` in the directory name.

### Error Handling

- **Version resolution failure** (GitHub API unreachable and `version=latest`): fatal, exit 1.
- **Checksum mismatch**: fatal, exit 1 (security boundary).
- **Missing arch**: if `uname -m` returns an unmapped value, log error and exit 1.
- **Extension install failure**: non-fatal warning. The feature's job is to install gh; extensions are
  best-effort post-install steps.
- **APT version not found**: `apt-get install gh=<version>` will fail naturally with a clear message.

---

## References

- [Installation Reference](installation.md) — methods, commands, asset naming, and official repo details
- [API Reference](api.md) — options, defaults, and usage examples
- [goreleaser.yml — CGO_ENABLED=0, archive structure, naming convention](https://github.com/cli/cli/blob/trunk/.goreleaser.yml)
- [Official Linux Install Docs](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
- [install-git scripts/install.sh — Platform dispatch and GPG key import patterns](../../src/install-git/scripts/install.sh)
- [install-pixi scripts/install.sh — Binary download + version resolution pattern](../../src/install-pixi/scripts/install.sh)
- [lib/github.sh — github__latest_tag, github__release_asset_urls](../../lib/github.sh)
- [lib/checksum.sh — checksum__verify_sha256](../../lib/checksum.sh)
- [lib/shell.sh — shell__detect_zshdir](../../lib/shell.sh)
- [lib/users.sh — users__resolve_list](../../lib/users.sh)
