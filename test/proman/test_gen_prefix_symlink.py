"""Tests for prefix_symlink's prefix-capable method selection.

A custom-prefix scenario must pin a method that honors `--prefix`; leaving it
`auto` can resolve to `package`/`upstream-package` (which install to a
PM-managed location and ignore `--prefix`), making every path assertion fail.
"""

from __future__ import annotations

from proman.test.gen.config import GenerationConfig
from proman.test.gen.facts import FeatureFacts
from proman.test.gen.rules.prefix_symlink import PrefixSymlinkRule

_ENVS = {
    "ubuntu-stable": {
        "attributes": {
            "os.id": "ubuntu",
            "plat.pm": "apt",
            "plat.kernel": "linux",
            "plat.machine_release": ["amd64", "arm64"],
        },
    },
    # A non-root env reuses ubuntu attributes; privilege is set by the runner.
    "ubuntu-stable+vscode": {"from": "ubuntu-stable"},
}

_CFG = GenerationConfig(
    enabled=True,
    rollout_mode="all",
    allowlist=frozenset(),
    denylist=frozenset(),
    primary_env="ubuntu-stable",
    nonroot_env="ubuntu-stable+vscode",
)


def _facts(methods: dict) -> FeatureFacts:
    return FeatureFacts(
        feature_id="install-fixture",
        verify={
            "args": "--version",
            "functional": {"description": "runs", "cmd": "{bin} --help"},
        },
        methods=methods,
        prefix={"bins": ["tool"]},
    )


def test_prefix_capable_methods_excludes_pm() -> None:
    """PM methods never count as prefix-capable, even without applies_when."""
    facts = _facts({"script": {}, "package": {}, "source": {}})
    assert facts.prefix_capable_methods == ["script", "source"]


def test_custom_prefix_pins_non_pm_method_without_applies_when() -> None:
    """No applies_when + a PM method: custom_prefix pins a non-PM method (rust bug)."""
    # Declared script-first with package present (install-rust shape).
    facts = _facts({"script": {}, "source": {}, "package": {}})
    scenarios = {s.name: s for s in PrefixSymlinkRule().generate(facts, _CFG, _ENVS)}
    root = scenarios["custom_prefix_symlink"]
    assert root.scenario["options"]["method"] == "script"
    assert root.scenario["options"]["method"] not in ("package", "upstream-package")


def test_pm_only_feature_skips_custom_prefix() -> None:
    """A PM-only feature has no prefix-capable method → no custom_prefix scenario."""
    facts = _facts({"package": {}, "upstream-package": {}})
    names = {s.name for s in PrefixSymlinkRule().generate(facts, _CFG, _ENVS)}
    assert "custom_prefix_symlink" not in names
    assert "custom_prefix_no_symlink" not in names


def _facts_with_build(methods: dict, build: dict) -> FeatureFacts:
    return FeatureFacts(
        feature_id="install-fixture",
        verify={
            "args": "--version",
            "functional": {"description": "runs", "cmd": "{bin} --help"},
        },
        methods=methods,
        prefix={"bins": ["tool"]},
        dependencies={"build": build},
    )


def test_build_packages_resolves_both_shapes() -> None:
    """PM-keyed and run-deps-style package lists both resolve for a PM."""
    pm_keyed = _facts_with_build(
        {"source": {}},
        {"method-source": {"apt": {"packages": ["build-essential", "libncurses-dev"]}}},
    )
    assert pm_keyed.build_packages("source", "apt") == [
        "build-essential",
        "libncurses-dev",
    ]
    pkg_list = _facts_with_build(
        {"source": {}},
        {"method-source": {"packages": ["make", {"name": "gcc", "apk": "build-base"}]}},
    )
    assert pkg_list.build_packages("source", "apt") == ["make", "gcc"]
    assert pkg_list.build_packages("source", "apk") == ["make", "build-base"]


def test_nonroot_custom_prefix_preinstalls_build_deps() -> None:
    """The nonroot custom-prefix setup pre-installs the pinned method's build deps."""
    facts = _facts_with_build(
        {"source": {}},
        {"method-source": {"apt": {"packages": ["build-essential", "libncurses-dev"]}}},
    )
    scenarios = {s.name: s for s in PrefixSymlinkRule().generate(facts, _CFG, _ENVS)}
    nonroot = scenarios["custom_prefix_symlink_nonroot"]
    setup = nonroot.scenario["setup"]
    assert "build-essential" in setup
    assert "libncurses-dev" in setup
    # Root custom-prefix installs build deps itself → no pre-install in setup.
    assert "setup" not in scenarios["custom_prefix_symlink"].scenario
