---
description: "Use when writing, editing, or creating feature installer scripts under src/**/scripts/ or shared library modules under lib/. Covers the bootstrap pattern, library sourcing, logging setup, dual-mode argument parsing, emoji conventions, and the full shared library API."
applyTo: "lib/*.sh"
---

# Shared Library

The `lib/` directory contains reusable POSIX-compliant and Bash-specific files that are sourced by feature installer scripts. They contain functions that abstract common operations, e.g. OS package installation, GitHub API calls, checksum verification, user management, and shell configuration.

<!-- START lib-api MARKER -->
| Module | Key API |
|---|---|
| `logging.sh` | `logging__setup` · `logging__mask_secret <value>` · `logging__tmpdir <name>` · `logging__cleanup` |
| `os.sh` | `os__kernel` · `os__arch` · `os__id` · `os__id_like` · `os__platform` · `os__require_root` · `os__font_dir` · `os__is_container` · `os__codename` |
| `ospkg.sh` | `ospkg__detect` · `ospkg__update [--force] [--lists_max_age N] [--repo_added]` · `ospkg__install <pkg>...` · `ospkg__clean` · `ospkg__parse_manifest_yaml <json-file>` · `ospkg__run [--manifest <f>] [--update <bool>] [--keep_cache] [--keep_repos] [--dry_run] [--skip_installed] [--interactive]` |
| `net.sh` | `net__fetch_with_retry [--retries N] [--delay N] <cmd...>` · `net__fetch_url_stdout <url> [--retries N] [--delay N] [--header <H>]...` · `net__fetch_url_file <url> <dest> [--retries N] [--delay N] [--header <H>]...` |
| `file.sh` | `file__extract_archive <archive_file> <dest_dir> [<original_name>]` |
| `git.sh` | `git__clone --url <url> --dir <dir> [--branch <branch>]` |
| `shell.sh` | `shell__detect_bashrc` · `shell__detect_zshdir` · `shell__write_block --file <f> --marker <id> --content <c>` · `shell__sync_block --files <list> --marker <id> [--content <c>]` · `shell__user_login_file [--home <dir>]` · `shell__system_path_files [--profile_d <filename>]` · `shell__detect_zdotdir [--home <dir>]` · `shell__user_path_files [--home <dir>] [--zdotdir <dir>]` · `shell__user_init_files [--home <dir>] [--zdotdir <dir>]` · `shell__user_rc_files [--home <dir>] [--zdotdir <dir>]` · `shell__system_rc_files` · `shell__resolve_omz_theme --theme_slug <slug> --custom_dir <dir>` · `shell__plugin_names_from_slugs <csv-slugs>` · `shell__resolve_home <username>` · `shell__ensure_bashenv` · `shell__create_symlink --src <s> --system-target <t> --user-target <t>` |
| `github.sh` | `github__fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>]` · `github__latest_tag <owner/repo>` · `github__release_tags <owner/repo> [--per_page N]` · `github__tags <owner/repo> [--per_page N]` · `github__release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere>]` · `github__pick_release_asset <owner/repo> [--tag <tag>] [--asset-regex <ERE>]` |
| `checksum.sh` | `checksum__verify_sha256 <file> <expected_hash>` · `checksum__verify_sha256_sidecar <file> <sha256_file>` |
| `users.sh` | `users__resolve_list` · `users__set_write_permissions <prefix> <owner> <group> [<user>...]` · `users__set_login_shell <shell_path> <username>...` |
<!-- END lib-api MARKER -->

`ospkg.sh` internally sources `os.sh` and `net.sh`, so sourcing `ospkg.sh` first is sufficient for most features. Source `github.sh`, `checksum.sh`, `shell.sh`, `git.sh`, and `users.sh` explicitly when needed.
