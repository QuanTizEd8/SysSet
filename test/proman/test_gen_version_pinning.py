"""Tests for the version_pinning rule's feasibility-aware method selection.

Guards that an exact-semver pin is assigned to a method that can actually
resolve that version host-side (binary/source/script/npm/cargo) rather than
`package`/`upstream-package` (which cannot), and that the resulting scenario
asserts the recorded installed-method.
"""

from __future__ import annotations

from proman.test.gen.config import GenerationConfig
from proman.test.gen.facts import FeatureFacts
from proman.test.gen.rules.version_pinning import VersionPinningRule

_ENVS = {
    "ubuntu-stable": {
        "attributes": {
            "os.id": "ubuntu",
            "plat.pm": "apt",
            "plat.kernel": "linux",
            "plat.machine_release": ["amd64", "arm64"],
        },
    },
}

_CFG = GenerationConfig(
    enabled=True,
    rollout_mode="all",
    allowlist=frozenset(),
    denylist=frozenset(),
    primary_env="ubuntu-stable",
    nonroot_env="ubuntu-stable",
)

_AMD_ARM = {"plat.machine_release": ["amd64", "arm64"]}


def _facts(methods: dict, pins: list[str]) -> FeatureFacts:
    return FeatureFacts(
        feature_id="install-fixture",
        # A functional smoke command is required by the comprehensive bundle
        # (assertions.functional_smoke_required) whenever methods/version exist.
        verify={
            "args": "--version",
            "functional": {"description": "tool runs", "cmd": "{bin} --help"},
        },
        methods=methods,
        version={"test_pins": {"pinned": pins}},
        prefix={"bins": ["tool"]},
    )


def _pin_titles(scenario) -> list[str]:  # noqa: ANN001
    return [c["title"] for c in scenario.checks["version_pinned"]["checks"]]


def test_exact_pin_excludes_package_even_when_declared_first() -> None:
    """A specific version is never pinned to `package` (can't resolve host-side)."""
    facts = _facts({"package": {}, "binary": {"when": _AMD_ARM}}, ["1.2.3"])
    scenarios = VersionPinningRule().generate(facts, _CFG, _ENVS)
    assert len(scenarios) == 1
    scenario = scenarios[0]
    assert scenario.scenario["options"]["method"] == "binary"
    assert any("installed-method state is binary" in t for t in _pin_titles(scenario))


def test_exact_pin_uses_canonical_priority_among_feasible() -> None:
    """Among feasible pin-capable methods, the canonical-first one is chosen."""
    # Declared source-first, but binary outranks source in canonical order.
    facts = _facts({"source": {}, "binary": {"when": _AMD_ARM}}, ["2.0.0"])
    scenario = VersionPinningRule().generate(facts, _CFG, _ENVS)[0]
    assert scenario.scenario["options"]["method"] == "binary"


def test_pin_scenario_asserts_installed_method_state() -> None:
    """Every pinned scenario asserts the recorded installed-method matches."""
    facts = _facts({"script": {}}, ["9.9.9"])
    scenario = VersionPinningRule().generate(facts, _CFG, _ENVS)[0]
    assert scenario.scenario["options"]["method"] == "script"
    assert any("installed-method state is script" in t for t in _pin_titles(scenario))
