"""Tests for the installer_dir and macos scenario families.

Locks in the two triage fixes from the Phase 3 gate: installer_dir asserts
`archive/` only for real tarball/zip releases (a single-binary release is moved
out of archive/), and macos_package_default is generated only for features whose
`package.when` explicitly names brew (unconstrained-`when` tools like jq/git are
pre-installed on the runner and skip the brew install).
"""

from __future__ import annotations

from proman.test.gen.config import GenerationConfig
from proman.test.gen.facts import FeatureFacts
from proman.test.gen.rules.installer_dir import InstallerDirRule
from proman.test.gen.rules.macos import MacosRule

_ENVS = {
    "ubuntu-stable": {
        "attributes": {
            "os.id": "ubuntu",
            "plat.pm": "apt",
            "plat.kernel": "linux",
            "plat.machine_release": ["amd64", "arm64"],
        },
    },
    "macos-current+brew": {
        "attributes": {
            "os.id": "macos",
            "plat.pm": "brew",
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
    macos_brew_env="macos-current+brew",
)

_AMD_ARM = {"plat.machine_release": ["amd64", "arm64"]}
_FUNC = {"description": "runs", "cmd": "{bin} --help"}


def _titles(scenario) -> list[str]:  # noqa: ANN001
    group = next(iter(scenario.checks.values()))
    return [c["title"] for c in group["checks"]]


def _binary_facts(asset_uri: str, *, sidecar: bool) -> FeatureFacts:
    binary = {"when": _AMD_ARM, "asset_uri": asset_uri}
    if sidecar:
        binary["sidecar_uri"] = "https://x/checksums.txt"
    return FeatureFacts(
        feature_id="install-tool",
        verify={"args": "--version", "functional": _FUNC},
        methods={"binary": binary},
        prefix={"bins": ["tool"]},
    )


def test_installer_dir_archive_check_for_tarball_release() -> None:
    """A .tar.gz release asserts archive/ is preserved (+ sidecar)."""
    facts = _binary_facts("https://x/tool_{feat.version}_linux.tar.gz", sidecar=True)
    scenario = InstallerDirRule().generate(facts, _CFG, _ENVS)[0]
    titles = _titles(scenario)
    assert "release archive preserved in installer_dir" in titles
    assert "checksum sidecar preserved in installer_dir" in titles
    assert "installer_dir preserves the download trace" not in titles


def test_installer_dir_preserves_trace_for_single_binary_release() -> None:
    """A single-binary release (no archive ext) asserts the trace dir, not archive/."""
    facts = _binary_facts("https://x/tool_{feat.version}_Linux_x86_64", sidecar=True)
    scenario = InstallerDirRule().generate(facts, _CFG, _ENVS)[0]
    titles = _titles(scenario)
    assert "installer_dir preserves the download trace" in titles
    assert "release archive preserved in installer_dir" not in titles


def test_installer_dir_conditional_extension_is_detected() -> None:
    """An asset_uri with the extension in a `{...?zip:tar.gz}` conditional counts."""
    facts = _binary_facts("https://x/tool.{kernel==mac?zip:tar.gz}", sidecar=False)
    titles = _titles(InstallerDirRule().generate(facts, _CFG, _ENVS)[0])
    assert "release archive preserved in installer_dir" in titles


def test_installer_dir_skips_package_only_feature() -> None:
    """A feature with no download method generates no installer_dir scenario."""
    facts = FeatureFacts(
        feature_id="install-tool",
        verify={"args": "--version", "functional": _FUNC},
        methods={"package": {}},
        prefix={"bins": ["tool"]},
    )
    assert InstallerDirRule().generate(facts, _CFG, _ENVS) == []


def _pkg_facts(when: object) -> FeatureFacts:
    return FeatureFacts(
        feature_id="install-tool",
        verify={"args": "--version", "functional": _FUNC},
        methods={"package": {"when": when}},
        prefix={"bins": ["tool"]},
    )


def test_macos_generates_for_explicit_brew_when() -> None:
    """package.when naming brew explicitly generates macos_package_default."""
    facts = _pkg_facts([{"plat.pm": "brew"}, {"plat.pm": "pacman"}])
    rule = MacosRule()
    assert rule.applies(facts, _CFG) is True
    scenarios = rule.generate(facts, _CFG, _ENVS)
    assert len(scenarios) == 1
    assert scenarios[0].name == "macos_package_default"
    assert scenarios[0].scenario["modes"] == ["macos"]


def test_macos_skips_unconstrained_when() -> None:
    """package.when=None (all PMs) does NOT apply — the tool may be pre-installed."""
    assert MacosRule().applies(_pkg_facts(None), _CFG) is False


def test_macos_skips_when_brew_not_named() -> None:
    """package.when constrained to non-brew PMs does not apply."""
    assert MacosRule().applies(_pkg_facts({"plat.pm": "apt"}), _CFG) is False
