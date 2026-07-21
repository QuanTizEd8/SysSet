"""Tests for feature install execution in the test runner."""

from __future__ import annotations

from pathlib import Path

from proman.test.run import (
    _option_env_value,
    _options_exports,
    _standalone_install_block,
)

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_option_environment_serialization_matches_feature_contract() -> None:
    """Booleans and array options reach installers in their documented forms."""
    for value, expected in ((True, "true"), (False, "false")):
        assert _option_env_value(value) == expected
    assert _option_env_value(["/first path", "/second"]) == "/first path\n/second"
    assert _options_exports({"backup-dir": ["/first path", "/second"]}) == (
        "export BACKUP_DIR='/first path\n/second'"
    )


def test_install_runner_declares_its_required_suite_tools() -> None:
    """The standard local command satisfies install setup_suite's cache contract."""
    source = (REPO_ROOT / ".dev/scripts/test/run-install.sh").read_text(
        encoding="utf-8"
    )
    assert "DEVFEATS_TEST_TOOL_CACHE=required" in source
    assert 'DEVFEATS_TEST_REQUIRED_TOOLS="jq yq"' in source
    assert "export DEVFEATS_TEST_TOOL_CACHE DEVFEATS_TEST_REQUIRED_TOOLS" in source


def test_standalone_install_streams_without_log_file() -> None:
    """Success-path standalone install runs without redirect or tee."""
    block = _standalone_install_block(
        "install-miniforge",
        "default",
        user="",
        expect_install_failure=False,
        failure_patterns=[],
    )
    assert "_FEATURE_INSTALL_LOG" not in block
    assert "tee" not in block
    assert "sh /repo/src/install-miniforge/install.sh" in block
    assert "FEATURE_INSTALL_RC=$?" in block


def test_standalone_install_failure_validation_tees_to_log() -> None:
    """Failure-path standalone install tees output for pattern validation."""
    block = _standalone_install_block(
        "install-miniforge",
        "invalid_version",
        user="",
        expect_install_failure=True,
        failure_patterns=["github__resolve_version: no release matching"],
    )
    assert 'tee "$_FEATURE_INSTALL_LOG"' in block
    assert '_FEATURE_INSTALL_RC_FILE="$(mktemp)"' in block
    assert 'FEATURE_INSTALL_RC="$(cat "$_FEATURE_INSTALL_RC_FILE")"' in block
    assert 'rm -f "$_FEATURE_INSTALL_RC_FILE"' in block
    assert "grep -Fq 'github__resolve_version: no release matching'" in block
    assert 'rm -f "${_FEATURE_INSTALL_LOG}"' in block
    assert "--- install output ---" not in block
