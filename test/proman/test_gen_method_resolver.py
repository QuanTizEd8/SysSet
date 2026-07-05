"""Tests for the generation-time METHOD=auto resolver port.

Pins the known cases the port must reproduce from the bash resolver
(`__resolve_auto_method__`), including the determinism, version-gating, and
package-channel behaviors that motivated it.
"""

from __future__ import annotations

from proman.test.gen.facts import FeatureFacts
from proman.test.gen.method_resolver import (
    CANONICAL_METHOD_ORDER,
    ResolveContext,
    classify_channel,
    declared_in_order,
    feasible_methods,
    is_feasible,
    resolve_auto_method,
)

# Representative env attribute sets (mirrors test/environments.yaml entries).
UBUNTU = {
    "os.id": "ubuntu",
    "plat.pm": "apt",
    "plat.kernel": "linux",
    "plat.libc": "gnu",
    "plat.machine_release": ["amd64", "arm64"],
}
ALPINE = {
    "os.id": "alpine",
    "plat.pm": "apk",
    "plat.kernel": "linux",
    "plat.libc": "musl",
    "plat.machine_release": ["amd64", "arm64"],
}
MACOS = {
    "os.id": "macos",
    "plat.pm": "brew",
    "plat.kernel": "darwin",
    "plat.machine_release": ["amd64", "arm64"],
}


def _facts(methods: dict, *, version: dict | None = None) -> FeatureFacts:
    return FeatureFacts(
        feature_id="install-fixture",
        methods=methods,
        version=version or {},
    )


# --- canonical order / determinism ------------------------------------------


def test_declared_order_is_canonical_not_dict_order() -> None:
    """Declared methods return in canonical order regardless of dict order."""
    methods = {"source": {}, "package": {}, "binary": {}}
    assert declared_in_order(_facts(methods)) == ["binary", "package", "source"]


def test_resolution_is_deterministic_under_key_shuffle() -> None:
    """Shuffling the method dict's key order must not change resolution."""
    a = _facts({"binary": {"when": {"plat.kernel": "linux"}}, "source": {}})
    b = _facts({"source": {}, "binary": {"when": {"plat.kernel": "linux"}}})
    ctx = ResolveContext(attrs=UBUNTU)
    assert resolve_auto_method(a, ctx) == resolve_auto_method(b, ctx) == "binary"


def test_unknown_method_names_appended_deterministically() -> None:
    """A non-canonical method name is appended (sorted), never dropped."""
    methods = {"zeta": {}, "binary": {}, "alpha": {}}
    assert declared_in_order(_facts(methods)) == ["binary", "alpha", "zeta"]


# --- channel classification --------------------------------------------------


def test_classify_channel() -> None:
    """Empty/stable → stable, latest → latest, any semver → specific."""
    assert classify_channel(None) == "stable"
    assert classify_channel("") == "stable"
    assert classify_channel("stable") == "stable"
    assert classify_channel("latest") == "latest"
    assert classify_channel("1.2.3") == "specific"
    assert classify_channel("1.2") == "specific"


# --- binary rust_triple + when gating ---------------------------------------


def test_binary_needs_rust_triple_only_when_templated() -> None:
    """rust_triple is required only when the asset URI templates it."""
    rust = _facts({"binary": {"asset_uri": "x-{plat.rust_triple}.tar.gz"}})
    plain = _facts({"binary": {"asset_uri": "x-{plat.machine_release}.tar.gz"}})
    no_triple = ResolveContext(attrs=UBUNTU, rust_triple=False)
    assert not is_feasible("binary", rust, no_triple)
    assert is_feasible("binary", plain, no_triple)


def test_binary_when_must_match_env() -> None:
    """A binary method's `when:` clause is matched against env attributes."""
    facts = _facts({"binary": {"when": {"plat.machine_release": ["amd64"]}}})
    arm_only = {**UBUNTU, "plat.machine_release": ["arm64"]}
    assert is_feasible("binary", facts, ResolveContext(attrs=UBUNTU))
    assert not is_feasible("binary", facts, ResolveContext(attrs=arm_only))


# --- version-gated binary (install-tokei shape) -----------------------------


def test_version_gated_binary_feasible_only_within_range() -> None:
    """A `feat.version`-gated binary is feasible only within its version range."""
    facts = _facts(
        {
            "binary": {
                "when": [
                    {"plat.kernel": "linux", "feat.version": {"lte": "12.1.2"}},
                ],
            },
            "cargo": {},
        },
    )
    in_range = ResolveContext(
        attrs=UBUNTU, version_channel="specific", resolved_version="12.1.2"
    )
    above = ResolveContext(
        attrs=UBUNTU, version_channel="specific", resolved_version="14.0.0"
    )
    unknown = ResolveContext(attrs=UBUNTU, version_channel="specific")
    assert is_feasible("binary", facts, in_range)
    assert not is_feasible("binary", facts, above)
    assert not is_feasible("binary", facts, unknown)


# --- package channel + privilege (install-zsh shape) ------------------------


def test_package_privilege_required_on_linux() -> None:
    """The `package` method needs privilege on Linux."""
    facts = _facts({"package": {}})
    root = ResolveContext(attrs=UBUNTU, privileged=True)
    nonroot = ResolveContext(attrs=UBUNTU, privileged=False)
    assert is_feasible("package", facts, root)
    assert not is_feasible("package", facts, nonroot)


def test_package_specific_version_needs_pm_availability() -> None:
    """A specific-version package request needs the PM to actually have it."""
    facts = _facts({"package": {}, "source": {}})
    unknown_pm = ResolveContext(attrs=UBUNTU, version_channel="specific")
    pm_has = ResolveContext(
        attrs=UBUNTU, version_channel="specific", pm_satisfies_specific=True
    )
    pm_missing = ResolveContext(
        attrs=UBUNTU, version_channel="specific", pm_satisfies_specific=False
    )
    assert not is_feasible("package", facts, unknown_pm)
    assert is_feasible("package", facts, pm_has)
    assert not is_feasible("package", facts, pm_missing)
    # zsh's package + exact-semver-with-no-PM-equivalent falls through to source.
    assert resolve_auto_method(facts, pm_missing) == "source"


def test_package_latest_channel_skipped() -> None:
    """The `package` method is skipped for the `latest` channel."""
    facts = _facts(
        {"package": {}, "binary": {"when": {"plat.machine_release": "riscv64"}}},
    )
    latest = ResolveContext(attrs=UBUNTU, version_channel="latest")
    assert not is_feasible("package", facts, latest)


# --- upstream-package stable-only -------------------------------------------


def test_upstream_package_stable_only() -> None:
    """The `upstream-package` method is feasible only on the stable channel."""
    facts = _facts({"upstream-package": {"when": {"plat.pm": "apt"}}})
    stable = ResolveContext(attrs=UBUNTU, version_channel="stable")
    specific = ResolveContext(attrs=UBUNTU, version_channel="specific")
    assert is_feasible("upstream-package", facts, stable)
    assert not is_feasible("upstream-package", facts, specific)


# --- npm-bundled / npm / cargo / git presence -------------------------------


def test_npm_bundled_excludes_alpine() -> None:
    """The `npm-bundled` method is feasible everywhere except alpine/musl."""
    facts = _facts({"npm-bundled": {}})
    assert is_feasible("npm-bundled", facts, ResolveContext(attrs=UBUNTU))
    assert not is_feasible("npm-bundled", facts, ResolveContext(attrs=ALPINE))


def test_npm_cargo_git_require_presence() -> None:
    """npm/cargo/git-clone are feasible only when the tool is pre-installed."""
    facts = _facts({"npm": {}, "cargo": {}, "git-clone": {}})
    bare = ResolveContext(attrs=UBUNTU)
    assert not is_feasible("npm", facts, bare)
    assert not is_feasible("cargo", facts, bare)
    assert not is_feasible("git-clone", facts, bare)
    provisioned = ResolveContext(
        attrs=UBUNTU, has_npm=True, has_cargo=True, has_git=True
    )
    assert is_feasible("npm", facts, provisioned)
    assert is_feasible("cargo", facts, provisioned)
    assert is_feasible("git-clone", facts, provisioned)


# --- darwin / macOS ----------------------------------------------------------


def test_package_feasible_on_macos_without_privilege() -> None:
    """Brew (package on darwin) needs no root; privilege is Linux-only."""
    facts = _facts({"package": {"when": {"plat.pm": "brew"}}})
    macos_nonroot = ResolveContext(attrs=MACOS, privileged=False)
    assert is_feasible("package", facts, macos_nonroot)


def test_resolve_prefers_binary_then_package_on_ubuntu() -> None:
    """Auto resolution prefers binary over package over source."""
    facts = _facts(
        {
            "package": {},
            "binary": {"when": {"plat.machine_release": ["amd64", "arm64"]}},
            "source": {},
        },
    )
    assert resolve_auto_method(facts, ResolveContext(attrs=UBUNTU)) == "binary"


def test_resolve_returns_none_when_nothing_feasible() -> None:
    """Auto resolution returns None when no declared method is feasible."""
    facts = _facts({"npm": {}, "cargo": {}})
    assert resolve_auto_method(facts, ResolveContext(attrs=UBUNTU)) is None


def test_feasible_methods_lists_all_in_priority_order() -> None:
    """feasible_methods returns every feasible method in priority order."""
    facts = _facts(
        {
            "source": {},
            "package": {},
            "binary": {"when": {"plat.machine_release": ["amd64", "arm64"]}},
        },
    )
    assert feasible_methods(facts, ResolveContext(attrs=UBUNTU)) == [
        "binary",
        "package",
        "source",
    ]


def test_canonical_order_matches_bash_resolver() -> None:
    """The canonical order must match __resolve_auto_method__'s loop exactly."""
    assert CANONICAL_METHOD_ORDER == (
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
