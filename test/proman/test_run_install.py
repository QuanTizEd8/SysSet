"""Tests for feature install execution in the test runner."""

from __future__ import annotations

from proman.test.run import _standalone_install_block


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
