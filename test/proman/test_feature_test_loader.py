"""Tests for proman.test.loader — feature test YAML validation."""

from __future__ import annotations

from pathlib import Path

import proman.config as cfg
import proman.test.loader as loader_mod
import pytest
import yaml
from proman.schema_bundle import clear_validator_cache
from proman.test.effective import EffectiveTests
from proman.test.loader import FeatureTestError, FeatureTestLoader

_REPO_ROOT = Path(__file__).resolve().parents[2]

_MINIMAL_MAIN = """\
name: Test
name_slug: test
owner: myowner
owner_slug: myowner
namespace: myowner/test
repo_url: https://github.com/myowner/test
oci_base: ghcr.io/myowner/test
docs:
  website_base_url: https://example.com/docs
path:
  features: features
  library: lib
  test_features: test/features
  test_features_shared_defaults: test/features/defaults.shared.yaml
  test_environments: test/environments.yaml
  shared_metadata: features/metadata.shared.yaml
  metadata_schema: features/metadata.schema.json
  checks_schema: test/features/checks.schema.json
  scenarios_schema: test/features/scenarios.schema.json
filename:
  feature_metadata: metadata.yaml
  feature_checks: checks.yaml
  feature_scenarios: scenarios.yaml
features:
  lifecycle_hook_keys:
    - onCreateCommand
"""


@pytest.fixture(autouse=True)
def _reset_config_singleton() -> None:
    yield
    cfg.clear_cache()
    clear_validator_cache()


@pytest.fixture
def repo_root(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Minimal repo layout with one feature test directory."""
    (tmp_path / ".config" / "proman").mkdir(parents=True)
    (tmp_path / ".config" / "proman" / "_main.yaml").write_text(
        _MINIMAL_MAIN,
        encoding="utf-8",
    )
    feat_test = tmp_path / "test" / "features" / "demo-feat"
    feat_test.mkdir(parents=True)
    (feat_test / "checks.yaml").write_text(
        yaml.dump(
            {
                "default": {
                    "checks": [
                        {"title": "ok", "cmd": "true"},
                    ],
                },
            },
        ),
        encoding="utf-8",
    )
    (feat_test / "scenarios.yaml").write_text(
        yaml.dump(
            {
                "default": {
                    "envs": ["ubuntu-24.04"],
                    "modes": ["standalone"],
                    "tests": ["default"],
                },
            },
        ),
        encoding="utf-8",
    )
    (tmp_path / "test" / "environments.yaml").write_text(
        "ubuntu-24.04:\n  image: ubuntu:24.04\n",
        encoding="utf-8",
    )
    (tmp_path / "test" / "features" / "defaults.shared.yaml").write_text(
        "options: {}\n",
        encoding="utf-8",
    )
    for rel in (
        "test/features/checks.schema.json",
        "test/features/scenarios.schema.json",
    ):
        src = _REPO_ROOT / rel
        dest = tmp_path / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")

    monkeypatch.setattr("proman.config.git_repo_root", lambda: tmp_path)
    cfg.clear_cache()
    clear_validator_cache()
    return tmp_path


def _loader() -> FeatureTestLoader:
    return FeatureTestLoader()


@pytest.mark.usefixtures("repo_root")
def test_load_accepts_minimal_layout() -> None:
    """Valid checks.yaml and scenarios.yaml pass schema and cross-file checks."""
    _loader().load("demo-feat")


def test_load_accepts_fully_generated_feature_without_test_dir(
    repo_root: Path,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A fully generated feature (no test dir on disk) loads via load_effective.

    Regression: the loader required an on-disk test dir + checks/scenarios
    files, so a dir-less generated feature (e.g. install-oras) raised
    "Feature test directory not found" even though load_effective yields its
    generated tests.
    """
    effective = EffectiveTests(
        feature_id="gen-feat",
        defaults={},
        scenarios={
            "default": {
                "envs": ["ubuntu-24.04"],
                "modes": ["standalone"],
                "tests": ["default"],
            },
        },
        checks={"default": {"checks": [{"title": "ok", "cmd": "true"}]}},
        provenance={"default": "generated"},
    )
    monkeypatch.setattr(loader_mod, "load_effective", lambda _fid: effective)
    # No test/features/gen-feat/ directory exists on disk.
    ft = _loader().load("gen-feat")
    assert set(ft.scenarios) == {"default"}


def test_load_rejects_missing_pattern(repo_root: Path) -> None:
    """install_failure checks require pattern in checks.yaml."""
    checks_path = repo_root / "test/features/demo-feat/checks.yaml"
    checks_path.write_text(
        yaml.dump(
            {
                "fail_case": {
                    "checks": [
                        {
                            "title": "install fails",
                            "kind": "install_failure",
                        },
                    ],
                },
            },
        ),
        encoding="utf-8",
    )
    scenarios_path = repo_root / "test/features/demo-feat/scenarios.yaml"
    scenarios_path.write_text(
        yaml.dump(
            {
                "fail_case": {
                    "envs": ["ubuntu-24.04"],
                    "modes": ["devcontainer"],
                    "expect_install_failure": True,
                    "tests": ["fail_case"],
                },
            },
        ),
        encoding="utf-8",
    )
    with pytest.raises(
        FeatureTestError,
        match="checks schema validation failed",
    ):
        _loader().load("demo-feat")


def test_load_rejects_devcontainer_runtime_checks(
    repo_root: Path,
) -> None:
    """expect_install_failure + devcontainer cannot reference runtime checks."""
    checks_path = repo_root / "test/features/demo-feat/checks.yaml"
    checks_path.write_text(
        yaml.dump(
            {
                "fail_case": {
                    "checks": [
                        {
                            "title": "install fails",
                            "kind": "install_failure",
                            "pattern": "boom",
                        },
                        {"title": "post-check", "cmd": "true"},
                    ],
                },
            },
        ),
        encoding="utf-8",
    )
    scenarios_path = repo_root / "test/features/demo-feat/scenarios.yaml"
    scenarios_path.write_text(
        yaml.dump(
            {
                "fail_case": {
                    "envs": ["ubuntu-24.04"],
                    "modes": ["devcontainer"],
                    "expect_install_failure": True,
                    "tests": ["fail_case"],
                },
            },
        ),
        encoding="utf-8",
    )
    with pytest.raises(
        FeatureTestError,
        match="only install_failure checks",
    ):
        _loader().load("demo-feat")


def test_load_rejects_network_failure_without_fast_net_fail(
    repo_root: Path,
) -> None:
    """Scenarios that expect network fetch failure must opt into fast retries."""
    checks_path = repo_root / "test/features/demo-feat/checks.yaml"
    checks_path.write_text(
        yaml.dump(
            {
                "blocked_net": {
                    "description": "Verify install fails when the network is blocked.",
                    "checks": [
                        {
                            "kind": "install_failure",
                            "title": "install fails when GitHub API is unreachable",
                            "pattern": "GitHub API unreachable",
                        },
                    ],
                },
            },
        ),
        encoding="utf-8",
    )
    scenarios_path = repo_root / "test/features/demo-feat/scenarios.yaml"
    scenarios_path.write_text(
        yaml.dump(
            {
                "blocked_net": {
                    "envs": ["ubuntu-24.04"],
                    "modes": ["standalone"],
                    "expect_install_failure": True,
                    "tests": ["blocked_net"],
                },
            },
        ),
        encoding="utf-8",
    )
    with pytest.raises(
        FeatureTestError,
        match="expects a network fetch failure",
    ):
        _loader().load("demo-feat")
