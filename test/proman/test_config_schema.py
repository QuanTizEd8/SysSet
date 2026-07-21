"""Tests for proman.cicd.config_schema.json — JSON Schema validation."""

import json
from pathlib import Path

import jsonschema
import proman.cicd.detect as cd
import pytest
from jsonschema.validators import Draft202012Validator

SCHEMA = json.loads((Path(cd.__file__).parent / "config_schema.json").read_text())
_VALIDATOR = Draft202012Validator(SCHEMA)


def _validate(instance: dict) -> None:
    """Validate *instance* against ``SCHEMA``."""
    _VALIDATOR.validate(instance)


def _make_valid_config() -> dict:
    """Build a fully-populated valid CI config dict."""
    return cd.build_config(
        build_image=True,
        image_name="ghcr.io/org/repo-devcontainer",
        image_tag="latest",
        ci_image="ghcr.io/org/repo-devcontainer:latest",
        run_lint=True,
        run_validate=True,
        run_unit=True,
        run_install=True,
        feature_matrix_raw=[
            {
                "feature": "install-git",
                "devcontainer_scenarios": ["default"],
                "linux_scenarios": ["default"],
                "macos_scenarios": [{"scenario": "mac", "runner": "macos-latest"}],
            },
        ],
        run_python=True,
        run_docs=True,
        is_release=False,
        features_to_release=[],
        unit_env_matrix=[
            {
                "name": "ubuntu-stable",
                "ordinary_env": "ubuntu-prepared",
                "bootstrap_env": "ubuntu-bare",
            },
        ],
        unit_macos_matrix=[
            {
                "env": "macos-current+brew",
                "runner": "macos-latest",
                "clean_path": True,
                "path_prepend": "/opt/homebrew/bin:/usr/local/bin",
                "integration": True,
            },
        ],
        install_env_matrix=[{"name": "ubuntu-stable", "env": "ubuntu-stable"}],
    )


def test_valid_config_passes() -> None:
    """Verify a fully-populated valid config passes schema validation."""
    _validate(_make_valid_config())


def test_missing_top_level_key_fails() -> None:
    """Verify schema validation fails when a required top-level key is absent."""
    cfg = _make_valid_config()
    del cfg["build_features"]
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)


def test_string_where_bool_required_fails() -> None:
    """Verify schema validation fails when a boolean field receives a string."""
    cfg = _make_valid_config()
    cfg["lint"]["shell"]["enabled"] = "true"
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)


def test_extra_key_fails_due_to_additional_properties() -> None:
    """Verify schema validation fails when an unknown key is added."""
    cfg = _make_valid_config()
    cfg["build_features"]["unknown_key"] = "x"
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)


def test_build_devcontainer_build_matrix_items_typed() -> None:
    """Verify build matrix items must have string fields."""
    cfg = _make_valid_config()
    cfg["build_devcontainer"]["build_matrix"] = [
        {"runner": 42, "platform": "x", "platform_tag": "y"},
    ]
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)


def test_deploy_features_list_typed() -> None:
    """Verify features list items must have string version fields."""
    cfg = _make_valid_config()
    cfg["deploy"]["features"] = [{"feature": "x", "version": 1, "tag": "x/1"}]
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)


def test_test_lib_linux_matrix_typed() -> None:
    """Library matrix items require both concrete profile environments."""
    cfg = _make_valid_config()
    cfg["test_lib"]["linux_matrix"] = [{"name": "x"}]
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)
    cfg["test_lib"]["linux_matrix"] = [
        {
            "name": "x",
            "ordinary_env": "x-prepared",
            "bootstrap_env": "x-bare",
            "tier": "lean",
        },
    ]
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)


def test_test_lib_linux_matrix_rejects_unsafe_or_empty_identifiers() -> None:
    """Linux scenario names are runtime-safe and environment keys are nonempty."""
    cfg = _make_valid_config()
    cfg["test_lib"]["linux_matrix"] = [
        {"name": "../unsafe", "ordinary_env": "prepared", "bootstrap_env": "bare"},
    ]
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)
    cfg["test_lib"]["linux_matrix"] = [
        {"name": "safe", "ordinary_env": "", "bootstrap_env": "bare"},
    ]
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)


def test_test_lib_macos_matrix_matches_emitted_shape() -> None:
    """A representative emitted macOS matrix entry validates."""
    cfg = _make_valid_config()
    cfg["test_lib"]["macos_matrix"] = [
        {
            "env": "macos-current+brew",
            "runner": "macos-26",
            "clean_path": True,
            "path_prepend": "/opt/homebrew/bin:/usr/local/bin",
            "integration": True,
        },
    ]
    _validate(cfg)


@pytest.mark.parametrize(
    "entry",
    [
        {
            "runner": "macos-26",
            "clean_path": True,
            "path_prepend": "",
            "integration": False,
        },
        {
            "env": 26,
            "runner": "macos-26",
            "clean_path": True,
            "path_prepend": "",
            "integration": False,
        },
        {
            "env": "macos-current",
            "runner": 26,
            "clean_path": True,
            "path_prepend": "",
            "integration": False,
        },
        {
            "env": "macos-current",
            "runner": "macos-26",
            "clean_path": "true",
            "path_prepend": "",
            "integration": False,
        },
        {
            "env": "macos-current",
            "runner": "macos-26",
            "clean_path": True,
            "path_prepend": [],
            "integration": False,
        },
        {
            "env": "macos-current",
            "runner": "macos-26",
            "clean_path": True,
            "path_prepend": "",
            "integration": "false",
        },
    ],
)
def test_test_lib_macos_matrix_rejects_missing_or_wrong_types(entry: dict) -> None:
    """Entries for macOS require every emitted field with its exact type."""
    cfg = _make_valid_config()
    cfg["test_lib"]["macos_matrix"] = [entry]
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)


def test_test_install_linux_matrix_typed() -> None:
    """Verify install linux_matrix items must include both name and env fields."""
    cfg = _make_valid_config()
    cfg["test_install"]["linux_matrix"] = [{"name": "x"}]  # missing "env"
    with pytest.raises(jsonschema.ValidationError):
        _validate(cfg)
