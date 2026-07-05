"""Generation-time port of the framework's `METHOD=auto` resolver.

Mirrors `__resolve_auto_method__` (features/install.tmpl.bash) so the generator
can, for a given environment + version input, compute *which* method a real
`auto` install would land on — and, symmetrically, whether an explicit
`(method, version, env)` combination is feasible at all.

This is the single source of truth for method selection in the generator,
replacing the previous reliance on `_options.method` dict-insertion order (which
is not a guaranteed-stable contract). The canonical priority order and the
per-method feasibility gates below are a direct, line-for-line transcription of
the bash resolver; keep them in sync — the generator self-tests
(`test/proman/test_gen_method_resolver.py`) pin the known cases.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING

from proman import when_util

if TYPE_CHECKING:
    from proman.test.gen.facts import FeatureFacts

# Exact priority order from __resolve_auto_method__'s `for _method in ...` loop.
# The generator must iterate methods in THIS order, never dict order.
CANONICAL_METHOD_ORDER: tuple[str, ...] = (
    "binary",
    "upstream-package",
    "package",
    "script",
    "npm-bundled",
    "npm",
    "cargo",
    "source",
    "git-clone",
)

# Version-input channels, mirroring __feat_auto_method_version_channel__: a bare
# empty/`stable` input is the stable channel; `latest` its own; anything else
# (a semver, partial or exact) is a "specific" version request.
CHANNEL_STABLE = "stable"
CHANNEL_LATEST = "latest"
CHANNEL_SPECIFIC = "specific"


def classify_channel(version_input: str | None) -> str:
    """Map a raw version input to its resolution channel (stable/latest/specific)."""
    if not version_input or version_input == "stable":
        return CHANNEL_STABLE
    if version_input == "latest":
        return CHANNEL_LATEST
    return CHANNEL_SPECIFIC


@dataclass(frozen=True)
class ResolveContext:
    """Everything the resolver needs about the environment + install request.

    Mirrors the runtime facts the bash resolver reads from the live system
    (`os__release_*`, `users__is_privileged`, `command -v npm/cargo/git`), made
    explicit here so resolution is a pure function of its arguments.
    """

    attrs: dict = field(default_factory=dict)
    """Flattened `test/environments.yaml` attributes for the target env
    (os.id, plat.kernel, plat.pm, plat.machine_release, ...)."""

    privileged: bool = True
    """Whether the install runs as root / with passwordless sudo. Base images
    run as root (True); the non-root `+vscode` envs are False."""

    has_npm: bool = False
    has_cargo: bool = False
    has_git: bool = False
    """Whether npm / cargo / git are already on PATH in this env (the pre-
    provisioned `npm_env` / `cargo_env`, or a base image that ships git)."""

    rust_triple: bool = True
    """Whether a Rust target triple resolves for this env's platform — required
    only by `binary` methods whose asset URI templates `{plat.rust_triple}`."""

    version_channel: str = CHANNEL_STABLE
    """Result of `classify_channel(version_input)` for the scenario."""

    resolved_version: str | None = None
    """The concrete version the scenario's input resolves to (from the live
    version-resolution layer), injected as `feat.version` when evaluating a
    method's `when:` clause — so `feat.version`-gated methods (e.g. tokei's
    `binary`, available only `<= 12.1.2`) are judged against the version
    actually being installed, not left permanently unmatched. `None` leaves
    `feat.version` absent, so a version-gated `when:` correctly does not match
    (unknown != satisfied)."""

    pm_satisfies_specific: bool | None = None
    """For a specific-version `package` request: whether the OS PM actually has
    a matching version (the in-container `ospkg__has_available_version` check).
    `None` = not determinable host-side; treated as not-feasible so the
    generator never emits a package scenario it can't confirm."""

    def kernel(self) -> str:
        """Lower-cased `plat.kernel` attribute (e.g. `linux`, `darwin`)."""
        return str(self.attrs.get("plat.kernel", "")).lower()

    def arches(self) -> set[str]:
        """Return `plat.machine_release` architectures as a lower-cased set."""
        raw = self.attrs.get("plat.machine_release", [])
        values = [raw] if isinstance(raw, str) else list(raw)
        return {str(v).lower() for v in values}

    def is_alpine(self) -> bool:
        """Mirror `os__platform == alpine` (the only platform npm-bundled excludes)."""
        return str(self.attrs.get("os.id", "")).lower() == "alpine"

    def match_attrs(self) -> dict:
        """Return `when:`-evaluation attrs with resolved_version as feat.version."""
        if self.resolved_version is None:
            return self.attrs
        return {**self.attrs, "feat.version": self.resolved_version}


def _binary_feasible(method_config: dict, ctx: ResolveContext) -> bool:
    # rust_triple gate only when the asset URI actually templates it.
    asset_uri = str(method_config.get("asset_uri", ""))
    if "{plat.rust_triple}" in asset_uri and not ctx.rust_triple:
        return False
    return when_util.match(method_config.get("when"), ctx.match_attrs())


def _pm_privilege_ok(ctx: ResolveContext) -> bool:
    # `[[ kernel != linux ]] || [[ privileged ]]`: PM methods need privilege on
    # Linux; on non-Linux (macOS/brew) privilege isn't required.
    return ctx.kernel() != "linux" or ctx.privileged


def _upstream_package_feasible(method_config: dict, ctx: ResolveContext) -> bool:
    if not _pm_privilege_ok(ctx):
        return False
    # Upstream repos aren't queryable before setup and won't track pre-releases
    # or specific versions: stable channel only.
    if ctx.version_channel != CHANNEL_STABLE:
        return False
    return when_util.match(method_config.get("when"), ctx.match_attrs())


def _package_feasible(method_config: dict, ctx: ResolveContext) -> bool:
    if not _pm_privilege_ok(ctx):
        return False
    if ctx.version_channel == CHANNEL_LATEST:
        return False  # PM won't have the very latest upstream release
    if ctx.version_channel == CHANNEL_SPECIFIC and not ctx.pm_satisfies_specific:
        return False  # requires an in-container ospkg__has_available_version hit
    return when_util.match(method_config.get("when"), ctx.match_attrs())


def _npm_bundled_feasible(ctx: ResolveContext) -> bool:
    if ctx.kernel() not in ("linux", "darwin"):
        return False
    if not (ctx.arches() & {"amd64", "arm64"}):
        return False
    return not ctx.is_alpine()


# One feasibility predicate per method, keyed by name — the Python equivalent of
# the bash resolver's `case "${_method}" in ...` dispatch. `mc` is the method's
# `_options.method.<name>` config dict (needed only for the when-gated methods).
_FEASIBILITY: dict[str, object] = {
    "binary": _binary_feasible,
    "upstream-package": _upstream_package_feasible,
    "package": _package_feasible,
    "script": lambda mc, ctx: True,  # noqa: ARG005
    "source": lambda mc, ctx: True,  # noqa: ARG005
    "npm-bundled": lambda mc, ctx: _npm_bundled_feasible(ctx),  # noqa: ARG005
    "npm": lambda mc, ctx: ctx.has_npm,  # noqa: ARG005
    "cargo": lambda mc, ctx: ctx.has_cargo,  # noqa: ARG005
    "git-clone": lambda mc, ctx: ctx.has_git,  # noqa: ARG005
}


def is_feasible(method: str, facts: FeatureFacts, ctx: ResolveContext) -> bool:
    """Return whether declared `method` is feasible under `ctx` (per the bash gates)."""
    method_config = facts.methods.get(method)
    predicate = _FEASIBILITY.get(method)
    if method_config is None or predicate is None:
        return False
    return bool(predicate(method_config, ctx))


def declared_in_order(facts: FeatureFacts) -> list[str]:
    """Return declared methods in canonical priority order (never dict order).

    Unknown/future method names not in `CANONICAL_METHOD_ORDER` are appended
    afterward, sorted, so output stays deterministic even for a method the
    resolver doesn't yet model.
    """
    declared = set(facts.methods)
    ordered = [m for m in CANONICAL_METHOD_ORDER if m in declared]
    extra = sorted(declared - set(CANONICAL_METHOD_ORDER))
    return ordered + extra


def feasible_methods(facts: FeatureFacts, ctx: ResolveContext) -> list[str]:
    """All declared methods feasible under `ctx`, in canonical priority order."""
    return [m for m in declared_in_order(facts) if is_feasible(m, facts, ctx)]


def resolve_auto_method(facts: FeatureFacts, ctx: ResolveContext) -> str | None:
    """Return the method a real `METHOD=auto` install would select under `ctx`.

    The first feasible declared method in canonical priority order, or `None`
    when none is feasible (mirroring the resolver's "No feasible method" error
    path).
    """
    for method in declared_in_order(facts):
        if is_feasible(method, facts, ctx):
            return method
    return None
