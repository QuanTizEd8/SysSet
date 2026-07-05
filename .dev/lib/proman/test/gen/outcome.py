"""The expected-outcome model — what a given install should produce.

Given a feature's facts, an environment/resolution context, and an install
request (method-or-auto, prefix, discovery, version input), computes the
*observable* outcome a real install must produce: which method resolves, which
version, where the binary lands, whether a symlink and/or a PATH-export block is
written, and the recorded `installed-method` state. Rules turn this into the
actual checks (see `checks_builtin`/`default_checks`), so a generated scenario
asserts the real result of the install rather than just "a binary exists".

Deliberately focused: shell **activation** and **completion** outputs are their
own option surfaces with dedicated families/augmentation, so they're not modeled
here. This module covers the universal install contract every method shares.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

from proman.test.gen import method_resolver

if TYPE_CHECKING:
    from proman.test.gen.facts import FeatureFacts
    from proman.test.gen.method_resolver import ResolveContext

# Methods that install a binary at `{prefix}/{bin_dir}/{bin}` and go through the
# framework's prefix/symlink/export machinery.
PREFIX_METHODS = frozenset({"binary", "source", "cargo", "npm", "npm-bundled"})
# Methods that install via the OS package manager to a PM-managed location
# (no prefix, no symlink/export — the PM puts the binary on PATH itself).
PM_METHODS = frozenset({"package", "upstream-package"})

# Directories that are always on PATH on our test images, so an install landing
# in one of them needs no symlink/export under `prefix_discovery=auto`. The
# non-root default bin dir (`~/.local/bin`) is on PATH in the +vscode envs.
_ROOT_PATH_DIRS = frozenset(
    {"/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"},
)


@dataclass(frozen=True)
class Symlink:
    """A predicted symlink: `link_path` -> `target` (the real install path)."""

    link_path: str
    target: str


@dataclass(frozen=True)
class ExpectedOutcome:
    """The observable result a scenario's install must produce."""

    method: str | None
    """Resolved install method (`request.method`, or the auto-resolved one).
    `None` when auto resolves to nothing feasible — the scenario is infeasible
    and should not be generated."""

    version: str | None = None
    """The concrete version to cross-validate against, when the scenario pins /
    resolves one. `None` leaves only a generic version-format check."""

    on_path: bool = True
    """Whether the primary binary is reachable via `command -v` afterward."""

    install_path: str | None = None
    """Absolute path of the installed binary, when predictable (prefix methods).
    `None` for PM-managed installs (assert `command -v` + PM-ownership instead)
    and for git-clone (no binary)."""

    pm_managed: bool = False
    """Whether the install is owned by the OS package manager."""

    symlink: Symlink | None = None
    """The symlink the install should create, or `None` when none is expected."""

    no_symlink_at: str | None = None
    """A link path that must NOT exist (for discovery modes that suppress the
    symlink), or `None` when there's nothing to assert absent."""

    path_export: bool = False
    """Whether a `/etc/profile.d/${_FEAT_PROFILE_D_FILE}` export block is written."""

    installed_method_state: bool = True
    """Whether `${_FEAT_SHARE_DIR_ROOT|NONROOT}/state/installed-method` is
    recorded (always true for a method-driven install)."""

    share_dir_var: str = "_FEAT_SHARE_DIR_ROOT"
    """Which share-dir env var the state file lives under (root vs non-root)."""

    git_clone: bool = False
    """Whether this is a git-clone install (directory outcome, not a binary)."""

    install_dir: str | None = None
    """For git-clone: the resolved clone directory."""


def _is_privileged(ctx: ResolveContext) -> bool:
    return ctx.privileged


def _share_var(ctx: ResolveContext) -> str:
    """Which share-dir env var holds the state file, root vs non-root."""
    return "_FEAT_SHARE_DIR_ROOT" if _is_privileged(ctx) else "_FEAT_SHARE_DIR_NONROOT"


def _resolved_prefix(
    facts: FeatureFacts,
    ctx: ResolveContext,
    prefix: str | None,
) -> str:
    """Return the prefix an install resolves to: explicit, else the default."""
    if prefix:
        return prefix
    if _is_privileged(ctx):
        return facts.default_prefix_root
    return facts.default_prefix_nonroot


def _symlink_dir(facts: FeatureFacts, ctx: ResolveContext) -> str:
    return facts.symlink_root if _is_privileged(ctx) else facts.symlink_nonroot


def _bin_dir_on_path(bin_dir: str, ctx: ResolveContext, facts: FeatureFacts) -> bool:
    if bin_dir in _ROOT_PATH_DIRS:
        return True
    # The non-root default bin dir is on PATH in the +vscode envs.
    return not _is_privileged(ctx) and bin_dir == facts.symlink_nonroot


def _wants_symlink(discovery: str, *, on_path: bool) -> bool:
    """Whether a symlink is created, per `prefix_discovery` semantics."""
    if discovery in ("symlink", "all"):
        return True
    if discovery in ("none", "shell"):
        return False
    # auto: skip if already on PATH, else create a symlink.
    return not on_path


def _wants_export(discovery: str) -> bool:
    """Whether a PATH-export block is written, per `prefix_discovery` semantics."""
    return discovery in ("shell", "all")


def _prefix_outcome(
    facts: FeatureFacts,
    ctx: ResolveContext,
    method: str,
    version: str | None,
    prefix: str | None,
    discovery: str,
) -> ExpectedOutcome:
    bin_name = facts.primary_bin
    resolved_prefix = _resolved_prefix(facts, ctx, prefix)
    install_bin_dir = f"{resolved_prefix}/{facts.bin_dir}"
    install_path = f"{install_bin_dir}/{bin_name}"
    on_path_dir = _bin_dir_on_path(install_bin_dir, ctx, facts)

    symlink: Symlink | None = None
    no_symlink_at: str | None = None
    link_path = f"{_symlink_dir(facts, ctx)}/{bin_name}"
    if not facts.symlink_skipped and _wants_symlink(discovery, on_path=on_path_dir):
        symlink = Symlink(link_path=link_path, target=install_path)
    elif link_path != install_path:
        # A discovery mode that suppresses the symlink — assert it's absent,
        # but only when the link path differs from the install path itself.
        no_symlink_at = link_path

    return ExpectedOutcome(
        method=method,
        version=version,
        on_path=on_path_dir or symlink is not None or _wants_export(discovery),
        install_path=install_path,
        pm_managed=False,
        symlink=symlink,
        no_symlink_at=no_symlink_at,
        path_export=_wants_export(discovery),
        share_dir_var=_share_var(ctx),
    )


def _pm_outcome(
    ctx: ResolveContext,
    method: str,
    version: str | None,
) -> ExpectedOutcome:
    return ExpectedOutcome(
        method=method,
        version=version,
        on_path=True,
        install_path=None,  # PM-managed; assert command -v + PM ownership
        pm_managed=True,
        share_dir_var=_share_var(ctx),
    )


def _git_clone_outcome(
    facts: FeatureFacts,
    ctx: ResolveContext,
    prefix: str | None,
) -> ExpectedOutcome:
    return ExpectedOutcome(
        method="git-clone",
        on_path=False,
        install_path=None,
        git_clone=True,
        install_dir=_resolved_prefix(facts, ctx, prefix),
        share_dir_var=_share_var(ctx),
    )


def compute(
    facts: FeatureFacts,
    ctx: ResolveContext,
    *,
    method: str | None = None,
    version: str | None = None,
    prefix: str | None = None,
    prefix_discovery: str = "auto",
) -> ExpectedOutcome | None:
    """Compute the expected outcome for one install request.

    `method=None` means `auto` — the resolved method is computed via
    `method_resolver`. `version` is the concrete resolved version to cross-
    validate (from `version_resolve`), or None. Returns `None` when the request
    is infeasible (auto resolves to nothing, or an explicit method isn't
    feasible under `ctx`) — the caller then skips generating that scenario.
    """
    if method is None:
        resolved = method_resolver.resolve_auto_method(facts, ctx)
    else:
        resolved = method if method_resolver.is_feasible(method, facts, ctx) else None
    if resolved is None:
        return None

    if resolved in PM_METHODS:
        return _pm_outcome(ctx, resolved, version)
    if resolved == "git-clone":
        return _git_clone_outcome(facts, ctx, prefix)
    if resolved in PREFIX_METHODS:
        return _prefix_outcome(facts, ctx, resolved, version, prefix, prefix_discovery)
    # script or any other method with no prefix/PM machinery: a plain binary on
    # PATH, location not separately predictable.
    return ExpectedOutcome(
        method=resolved,
        version=version,
        on_path=True,
        share_dir_var=_share_var(ctx),
    )
