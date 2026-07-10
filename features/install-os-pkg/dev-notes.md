# Developer Notes

Internal reference for contributors: the design rationale, architectural
decisions, and implementation details behind the manifest format and Homebrew
integration. It complements the user-facing `notes.md` with the _why_ behind
the design.

## Design rationale: why YAML

An earlier text DSL used custom section headers (`--- type [selectors]`) and
per-line selectors (`package [key=val]`). It worked for basic cases but had
fundamental limits that motivated the move to YAML:

1. **No tooling support.** Custom syntax is invisible to linters, formatters,
   language servers, and IDEs — no autocompletion, no validation, unhelpful
   errors.

2. **Flat structure.** Package-specific setup (keys, repos, scripts) had to
   live in separate sections scattered across the file. There was no way to
   co-locate all setup for one third-party package (Docker CE alone needs a
   key + repo + package + post-install script).

3. **Homebrew complexity.** Brew introduces taps, casks, and the `--cask`
   flag that do not map cleanly onto a `pkg`/`repo`/`key` section model. Taps
   are Git clones, casks are not regular packages, and brew has no signing
   keys.

4. **Extensibility ceiling.** Adding per-PM constructs (PPAs, COPR, modules,
   groups) to a line-oriented format would require ever more complex
   header/selector syntax — a bespoke DSL harder to learn than a structured
   format users already know.

YAML was chosen over other structured formats because:

- **A YAML pipeline was already proven in the codebase** — `yq` bootstrap plus
  YAML→JSON→`jq` processing. `lib/ospkg.bash` reuses the same shared
  infrastructure (see [YAML parser infrastructure](#yaml-parser-infrastructure)).
- **JSON Schema gives a machine-verifiable contract** — one schema file is the
  authoritative spec, validation source, documentation basis, and IDE
  autocompletion backend.
- **YAML is natively commentable** — unlike JSON, which matters for
  hand-maintained manifests.
- **One file replaces many** — a single manifest replaces the per-platform
  files features previously maintained.

JSON manifests are equally valid (JSON is a subset of YAML). The parser uses
`yq`, which auto-detects the format, so no extension convention or explicit
flag is needed.

## Schema design

### Evaluated candidates

Many schema shapes were evaluated during design. The major categories:

- **Flat package list** with per-entry PM overrides — every package becomes an
  object, making simple manifests needlessly verbose.
- **PM-first grouping** (`apt: {packages}`, `brew: {packages}`) — clean for
  PM-specific packages but forces duplication for cross-platform packages
  (cannot express "install `curl` everywhere" without repeating it).
- **Separate `overrides` section** — splits logically related information
  across distant parts of the file.
- **Brewfile-inspired DSL** — Ruby-like entries (`brew "bat"`) embedded in
  YAML strings; foreign syntax that defeats the point of a structured format.
- **conda `meta.yaml` selectors** (`# [osx]`) — clever but fragile, invisible
  to YAML parsers, and unvalidatable by JSON Schema.

### Selected: unified `packages` + PM-scoped blocks

The chosen shape balances simplicity, expressiveness, and cross-PM coverage:

- **`packages`** is the primary, PM-agnostic array. The 95% case — a list of
  names — is a plain YAML list with no objects or nesting.
- **Package objects** add PM-specific overrides inline, right where the package
  is defined — no cross-referencing a separate section.
- **PM blocks** (`apt:`, `brew:`, ...) encapsulate inherently PM-specific
  operations (PPAs, taps, casks, COPR, modules) and are naturally exclusive —
  only the active PM's block runs.
- **Groups** factor out shared `when`/`flags` without repeating them on every
  entry.

This layered design scales from a 3-line manifest to a 50-line cross-platform
configuration without syntactic overhead at either end.

### Refinements to the base schema

1. **`when` as object OR array-of-objects.** Real manifests need OR across
   different key combinations — e.g. "(Ubuntu AND apt) OR (Fedora AND dnf)."
   The array-of-objects form provides this with no new keyword and no boolean
   expression parser.

2. **Group objects.** When many packages share a condition or flags, repeating
   them is noisy and error-prone. Groups factor out shared properties and nest
   for hierarchical conditions. A group with no `packages` is a pure
   conditional carrier for keys/repos/scripts.

3. **Inline setup on packages/groups.** Third-party packages often need a key,
   a repo, and a post-install script. The inline `keys`/`repos`/`script`/
   `prescript` properties let all setup for one logical package live together;
   items are collected and merged into the standard pipeline phases, so
   execution order is unchanged.

## `when` clause design

The `when` clause reads from the unified condition context (`os.*`, `plat.*`,
`feat.*`) shared across the whole framework, not a manifest-local vocabulary.
Keys are **qualified** (`os.id`, `plat.pm`, `feat.version`) and validated by
the schema's `^(os|plat|feat)\.[a-z0-9_]+$` pattern; legacy flat keys (`pm`,
`arch`, `id`, ...) are rejected outright. This is the same context registry
(`lib/ctx.bash`) that feature `metadata.yaml` `when` blocks read from.

Selector mechanisms from other ecosystems informed the design:

| System | Mechanism | Scope |
|---|---|---|
| Homebrew Brewfile | Ruby conditionals (`if OS.mac?`) | Per-entry, arbitrary Ruby |
| conda `meta.yaml` | Jinja2 comment selectors (`# [osx]`) | Per-line comment |
| rattler-build | `if/then` YAML keys | Per-section |
| APT `sources.list` | `[arch=amd64]` options | Per-repo line |
| **manifest `when`** | **object / array-of-objects over qualified keys** | **Per-entry, per-group** |

Design choices:

- **Declarative over procedural.** Brewfile uses Ruby and conda uses Jinja2 —
  powerful but impossible to validate statically. `when` clauses are pure data,
  fully validatable via JSON Schema.
- **Qualified key vocabulary.** Keys are namespaced facts drawn from the shared
  context registry (`os.*` from os-release, `plat.*` from host detection,
  `feat.*` from install context) rather than free-form predicates. This avoids
  the ambiguity of conda's overlapping `osx`/`unix`/`linux` identifiers and
  lets manifests reuse the exact keys features already use elsewhere.
- **Explicit operators.** Beyond string/array equality, keys accept an operator
  object (`eq`, `ne`, `lt`, `lte`, `gt`, `gte`) for semver-ordered comparisons
  on version-like fields.
- **AND/OR composability** with no expression parser: object = AND, array = OR.
- **No negation.** There is deliberately no `not` — negation makes manifests
  fragile against new platforms (`not: apt` silently includes every future PM).
  Positive assertions are forward-compatible.

## `when` evaluation

Evaluation is delegated to the shared context layer (`ctx__match_when` /
`ctx-match.jq`), the same engine used for feature `when` blocks — `ospkg.bash`
does not implement its own matcher. The semantics:

1. **Absent `when`** → always matches.
2. **Single object** → AND across keys; within a key, a scalar must match
   (case-insensitive), an array matches if any element matches (OR), and an
   operator object ANDs its present operators.
3. **Array of objects** → OR; matches if any element matches.
4. **Group stacking** → a group's `when` ANDs with each child's `when`; nested
   groups stack, and a failing ancestor short-circuits the whole subtree.

`os.id_like` is matched by token membership over the whitespace-separated
`ID_LIKE` list; ordering operators on it always fail (fail-closed).

## PM detection chain

`_ospkg__detect` selects the first PM binary present in `PATH`:

```
apt-get → apk → dnf → microdnf → yum → zypper → pacman → brew
```

`brew` is last because native PMs are faster, better integrated, and produce
smaller images than Linuxbrew; a Linux host with both `apt-get` and `brew` is
almost always a workstation where the native PM is the right default. Set
`prefer_linuxbrew: true` to check `brew` first. On macOS the linear chain is
skipped — `brew` is the only candidate, and its absence is a hard error rather
than a silent no-op.

`microdnf` is detected only when `dnf` is absent (RHEL/UBI minimal images ship
`microdnf` but not `dnf`), so standard RHEL images keep using `dnf`. Because
`microdnf` lacks the `copr` and `module` subcommands, those manifest features
are skipped with a warning under `microdnf`/`yum`.

## Brew root handling

Homebrew refuses to run as root on bare metal but **explicitly allows root in
containers**. From brew's `check-run-command-as-root()`
(`Library/Homebrew/brew.sh`):

```bash
[[ "${EUID}" == 0 || "${UID}" == 0 ]] || return
[[ -f /.dockerenv ]] && return
[[ -f /run/.containerenv ]] && return
[[ -f /proc/1/cgroup ]] && grep -E \
  "azpl_job|actions_job|docker|garden|kubepods" -q /proc/1/cgroup && return
```

A devcontainer feature's `install.sh` always runs as root, so the installer
leverages brew's own container detection to run `brew install` directly as root
inside containers — no user switching. The devcontainer spec's `_REMOTE_USER` /
`_CONTAINER_USER` are irrelevant here; only the brew-prefix owner matters, and
only on bare metal.

## Brew user handling

Who runs `brew` is decided by three facts: effective UID, container status,
and brew-prefix ownership.

| Context | EUID | Container? | Action |
|---|---|---|---|
| Devcontainer feature | 0 | Yes | Run brew directly (allowed) |
| Standalone on bare metal | 0 (sudo) | No | `su` to owner of `$(brew --prefix)` |
| Normal user | ≠ 0 | — | Run brew directly |

This is handled inside `ospkg.bash`; no user-facing `brew_user` option is
exposed. The prefix owner is deterministic (obtainable via `stat`), so an
option would only invite error. Container detection reuses
`os__is_container()` in `lib/os.bash`, checking the same indicators brew does:
`/.dockerenv`, `/run/.containerenv`, and cgroup entries for `docker`,
`kubepods`, `garden`, `azpl_job`, `actions_job`.

## YAML parser infrastructure

Manifest parsing is a `yq` + `jq` pipeline:

1. **`yq`** (mikefarah) reads the manifest and emits JSON, auto-detecting YAML
   vs JSON. `yq` is ensured on demand by the shared `bootstrap__yq`
   bootstrapper — fetched for the current platform/arch, checksum-verified, and
   cached without a system install or `PATH` change.
2. **`jq`** (via the `json__query` wrapper) runs `lib/ospkg-manifest.jq`, which
   normalizes the JSON into the flat phase arrays consumed by bash
   (`_Y_PRESCRIPTS`, `_Y_KEYS`, `_Y_REPOS`, `_Y_PPAS`, `_Y_TAPS`, `_Y_COPR`,
   `_Y_MODULES`, `_Y_GROUPS`, `_Y_PACKAGES`, `_Y_CASKS`, `_Y_SCRIPTS`).

`when` evaluation and `{namespace.key}` token expansion are handled by the
shared `lib/ctx.bash` / `ctx-match.jq` layer, not by ospkg-specific code.

## Collected ordering

Inline `keys`/`repos`/`scripts` from packages and groups are merged into their
pipeline phases in **manifest declaration order**. Within a phase the merge
order is:

1. PM-block entries for the active PM.
2. Top-level entries (`prescripts`, `scripts`, `keys`, `repos`, ...).
3. Inline entries collected from `packages`, depth-first through nested groups,
   in declaration order.

So a PM block's keys are fetched before a package's inline keys, and a key on
an earlier package is fetched before one on a later package.

## Backward compatibility

The text DSL parser was removed as a **clean break** — no transition period,
compatibility layer, or auto-migration. Rationale:

- **No external users.** The feature had no stable release; the text DSL was
  never documented outside this repo or published to a registry.
- **All in-repo manifests were migrated.** The package manifests that other
  features consume are now generated from `_dependencies` in each feature's
  `metadata.yaml` (against this same schema), so there was nothing to keep
  compatible.
- **Two parsers would be costly** — confusing errors, silent misinterpretation,
  and indefinite documentation burden for a deprecated syntax.
- **Clean breaks are cheap pre-release.** The JSON Schema now provides the
  versioned contract that guards against future breakage.

## Cross-PM feature mapping

Not every PM concept maps across managers. Entries marked "—" do not exist for
that PM and are silently skipped:

| Concept | apt | apk | brew | dnf | yum | pacman | zypper |
|---|---|---|---|---|---|---|---|
| Regular packages | `apt-get install` | `apk add` | `brew install` | `dnf install` | `yum install` | `pacman -S` | `zypper install` |
| GUI apps (casks) | — | — | `brew install --cask` | — | — | — | — |
| Third-party repos | `sources.list.d/` | `/etc/apk/repositories` | `brew tap` | `yum.repos.d/` | `yum.repos.d/` | `pacman.conf` | `zypper addrepo` |
| PPAs | `add-apt-repository` | — | — | — | — | — | — |
| COPR | — | — | — | `dnf copr enable` | — | — | — |
| Module streams | — | — | — | `dnf module enable` | — | — | — |
| Package groups | — | — | — | `dnf group install` | `yum groupinstall` | `pacman -S <group>` | `zypper install -t pattern` |
| Signing keys (fetched → `dest`, dearmored if `.gpg`; ospkg never runs `rpm --import`/`pacman-key`) | `signed-by=` keyring | `/etc/apk/keys/` | — | `gpgkey=` file | `gpgkey=` file | keyring file | keyring file |
| Cache clean | `apt-get clean` | `apk cache clean` | `brew cleanup` | `dnf clean all` | `yum clean all` | `pacman -Scc` | `zypper clean` |
| List update | `apt-get update` | `apk update` | `brew update` | `dnf makecache` | `yum makecache` | `pacman -Sy` | `zypper refresh` |
