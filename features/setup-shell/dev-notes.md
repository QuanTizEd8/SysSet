# Implementation Reference

This feature deploys system-wide and per-user shell configuration for Bash and
Zsh. It is built from a **block/target registry** rather than monolithic template
files, so every configuration section is an independently toggleable, marker-
wrapped block with its own per-target lifecycle.

## Architecture

- **`_internal.blocks` / `_internal.targets`** (in [`metadata.yaml`](metadata.yaml))
  — the catalog. `blocks` maps a block id to its metadata (marker, `kind:
  fixed|dynamic`, backing `slice`/`dynamic` function, `option`, `option_type`,
  `inject_anchor`). `targets` is the ordered list of deploy targets, each with a
  `lifecycle_scope` (`system|skel|user|line`), a path (via `default_path`,
  `deploy_option`, or `path_resolver`), a `when` gate, and an ordered `blocks`
  list.
- **Codegen** — pyserials templates in `metadata.yaml` generate (a) the ~64
  `block_*` options from the catalog (via the `? |…| :` complex-key, mirroring
  `metadata.shared.yaml`'s `ospkg_manifest_*`), and (b) `files/blocks.registry.bash`
  (via `_files`), which populates the `_FEAT_SS_*` bash associative arrays the
  engine reads. Both are single-sourced from the catalog — never hand-edit the
  generated registry.
- **`files/blocks/*.slice`** — the fixed content for `kind: fixed` blocks, split
  from the original monolithic config files. `kind: dynamic` blocks are rendered
  by `_dyn_*` functions in [`install.bash`](install.bash) (they read option
  values / per-user context at apply time).
- **`files/lifecycle.bash`** — the registry-driven apply/probe/uninstall engine.
- **[`install.bash`](install.bash)** — feature glue: deploy-gate predicates,
  path resolvers (`_ss_resolve_*`), target `when` gates (`_ss_target_*`), dynamic
  content (`_dyn_*`), the dispatch override, and `__configure_user`.

## Lifecycle (per target, per block)

Three knobs, each resolving `auto` (devcontainer→`reinstall`, standalone→
`update`) independently; `if_exists_skel`/`if_exists_user` default `inherit`
(copy the resolved `if_exists_sys`):

| Knob | Scope |
|------|-------|
| `if_exists_sys` | system files + `/etc/environment` line |
| `if_exists_skel` | `/etc/skel/*` |
| `if_exists_user` | live per-user dotfiles |

| Mode | Behavior |
|------|----------|
| `skip` | Absent → assemble enabled blocks; exists → zero writes. |
| `update` | Absent → assemble; exists → per block inject / sync-if-content-differs / remove-if-disabled. Non-managed bytes never touched. |
| `reinstall` | Whole-file replace from enabled blocks; backs up any existing file first (`backup`/`backup_dir` options, via `file__backup_if_policy`). If every block of a target is disabled (empty assembly), the existing file is left untouched rather than emptied. |
| `fail` | Probe pass first across every fail-scoped target (system/skel/user); a conflict in **any** scope aborts the whole run with zero writes. |
| `uninstall` | Strip every block's marker; delete the file iff whitespace-only afterwards. |

A `fail` conflict = the target exists and a block would inject, sync (rendered
content differs from what's on disk), or remove. Absent paths are never a
conflict.

## Dispatch

setup-shell has no installed binary and no `METHOD`, so it **overrides
`__if_exists_dispatch__`** and never reaches the framework's binary/version-
oriented `__update_run__`/`__reinstall_run__` (which fatal without a `METHOD`).
`__init_args_post` sets a synthetic `IF_EXISTS` (uninstall vs. install) so the
framework routes to the override, which dispatches purely on `IF_EXISTS_SYS`.

The shared framework `if_exists` option (from `metadata.shared.yaml`) is
otherwise unused by setup-shell — its real knobs are `if_exists_sys/_skel/_user`
— but `if_exists=uninstall` is still honored as an uninstall trigger.

## Block toggles

Every `block_*` option defaults `true`; opt out per section with `block_*:
false`. String/enum blocks (`block_sys_shellenv_umask`, `_locale`, `_editor`,
`_path_baseline`, the six `_xdg_*`) exclude their block when empty (or `skip` for
the editor enum). Deploy-path options (`sys_*`, `user_*`) set *where* a file
lives; empty = skip that file and its source hooks (except `sys_bashenv` /
`sys_shellcompletions`, whose empty default means "auto-detect the path").

## Inject anchors

On `update` of a pre-existing foreign file, a block's first inject is placed by
its `inject_anchor` (`shell__resolve_inject_line_v1`):

- `file-top-after-comments` — after leading comments (e.g. `profile-shellenv`).
  Existing marker blocks are skipped so a second top-anchored inject stacks
  below a previous one instead of landing inside its markers.
- `after-interactivity-guard-or-eof` — after a `case $- in … esac` guard, else
  EOF. Guards **inside existing marker blocks are skipped** so our own injected
  guard block isn't matched (which would nest subsequent blocks inside it).
- `eof` — appended at end of file (default for user dotfiles).

`shell__insert_block_at_line` appends at true EOF when the anchor line exceeds
the file length (the anchor came up empty) — a safe fallback, since wiring
blocks after a foreign guard's `return` are skipped exactly when the guard
already skipped everything else.

**Inject order is registry order in every case**: when the guard anchor matches
an interior line, first-time injects are applied bottom-up (reverse registry
order at a fixed anchor line ⇒ final file order = registry order); when the
anchor falls back to EOF — e.g. stock Debian bashrc, which has no `case $-`
guard — sequential appends already stack in registry order.

## Sibling features

- Login-shell setting moved off setup-shell: `install-bash` / `install-zsh` each
  have `set_login_shell` (boolean, default `true`), implemented as a
  `__configure_user` hook so it honors the four `add_*` options and fires under
  `if_exists=skip`.
- `install-zsh-completion` writes its `fpath` block into `sys_shellcompletions`
  (resolved dynamically via `shell__detect_zshdir` — matches setup-shell across
  distros, not just Debian). Customizing `sys_shellcompletions` requires a
  matching `rcfile` there.

## Testing (golden fixtures)

The key scenarios use **golden-file** tests: `test/features/setup-shell/expected/<scenario>/`
holds the reviewed, committed deployed tree, and `support/assert_golden.sh`
diffs the live filesystem against it (byte-for-byte, symmetric — it also fails
on any setup-shell-managed file that has *no* fixture, catching over-deployment).
Golden runs are **standalone-only**: the feature test dir is bind-mounted into
the container only in standalone mode (`.dev/lib/proman/test/run.py`).

Regenerate with `python3 test/features/setup-shell/generate_golden.py
[--scenario KEY]`. **Never commit a regenerated fixture without reviewing the
diff** — fixtures are produced by the same installer the tests exercise, so an
unreviewed regeneration would bake a regression in as "correct."

Narrow assertions, devcontainer smoke, and the `if_exists=fail` install-failure
case use ordinary declarative checks in `checks.yaml`.

## Design decisions of record

- **`setup_skel` is independent of `setup_system`** (deliberate): `/etc/skel`
  templates deploy whenever `setup_skel` allows, even with
  `setup_system: false`. `setup_system` governs only the live system config
  files; the option descriptions state this explicitly.
- **Backups**: `reinstall` backs up an existing file before replacing it
  (`backup` policy, default `auto`: skip inside devcontainers/Codespaces).
  System/skel backups go to the first writable `backup_dir` candidate;
  per-user dotfile backups go to each target user's own share dir.

## Deferred (v1 stubs / accepted gaps)

- **Block preconditions** (content-based duplicate detection) are deferred:
  `_block_precondition_met` is a v1 no-op; the `precondition` registry field is
  reserved. Opt-out on foreign distro files is via `block_*: false` only.
- **No 0.1.0 migration**: marker renames / outer-marker removal are a clean
  break (unreleased prerelease). Upgrade = uninstall old version first.

**Prior design doc:** superseded Cursor plan at
`.cursor/plans/setup-shell_lifecycle_semantics_610e8ef4.plan.md`.
