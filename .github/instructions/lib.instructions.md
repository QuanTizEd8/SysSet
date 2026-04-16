---
description: "Use when writing, editing, or creating feature installer scripts under src/**/scripts/ or shared library modules under lib/. Covers the bootstrap pattern, library sourcing, logging setup, dual-mode argument parsing, emoji conventions, and the full shared library API."
applyTo: "lib/*.sh"
---

# Shared Library

The `lib/` directory contains reusable POSIX-compliant and Bash-specific files that are sourced by feature installer scripts. They contain functions that abstract common operations, e.g. OS package installation, GitHub API calls, checksum verification, user management, and shell configuration.

| Module | Key API |
|---|---|
| `logging.sh` | `logging__setup` · `logging__cleanup` |
| `os.sh` | `os__require_root` · `os__kernel` · `os__arch` · `os__id` · `os__id_like` · `os__platform` · `os__font_dir` |
| `ospkg.sh` | `ospkg__detect` · `ospkg__install <pkg>...` · `ospkg__update` · `ospkg__clean` · `ospkg__run [--manifest <f>] [--check_installed] [--no_clean] [--no_update] [--dry_run]` |
| `net.sh` | `net__fetch_url_stdout <url>` · `net__fetch_url_file <url> <dest>` · `net__fetch_with_retry <n> <cmd...>` |
| `git.sh` | `git__clone --url <url> --dir <dir> [--branch <branch>]` |
| `shell.sh` | `shell__detect_bashrc` · `shell__detect_zshdir` · `shell__resolve_home <user>` · `shell__resolve_omz_theme` · `shell__plugin_names_from_slugs <csv>` · `shell__write_block` · `shell__remove_block` · `shell__export_path` · `shell__export_env` |
| `github.sh` | `github__fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>]` · `github__latest_tag <owner/repo>` · `github__release_tags <owner/repo> [--per_page <n>]` · `github__release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere>]` |
| `checksum.sh` | `checksum__verify_sha256 <file> <expected_hash>` · `checksum__verify_sha256_sidecar <file> <sha256_file>` |
| `users.sh` | `users__resolve_list` · `users__set_login_shell <shell_path> <username>...` |

`ospkg.sh` internally sources `os.sh` and `net.sh`, so sourcing `ospkg.sh` first is sufficient for most features. Source `github.sh`, `checksum.sh`, `shell.sh`, `git.sh`, and `users.sh` explicitly when needed.
