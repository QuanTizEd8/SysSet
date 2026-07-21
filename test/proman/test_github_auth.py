"""Tests for GitHub credential normalization used by test runners."""

# Test names state their contracts; repeating each as a one-line docstring adds noise.
# Dummy token values are deliberately non-secret test fixtures.
# ruff: noqa: D103, S105

from __future__ import annotations

import subprocess
from typing import TYPE_CHECKING

from proman.test import github_auth

if TYPE_CHECKING:
    import pytest


def test_existing_github_token_is_preserved(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("GITHUB_TOKEN", "existing-token")
    monkeypatch.setenv("GH_TOKEN", "alternate-token")
    monkeypatch.setattr(
        github_auth.subprocess,
        "run",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError),
    )

    assert github_auth.ensure_github_token()
    assert github_auth.os.environ["GITHUB_TOKEN"] == "existing-token"


def test_gh_token_is_normalized_without_invoking_cli(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    monkeypatch.setenv("GH_TOKEN", "alternate-token")
    monkeypatch.setattr(
        github_auth.subprocess,
        "run",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError),
    )

    assert github_auth.ensure_github_token()
    assert github_auth.os.environ["GITHUB_TOKEN"] == "alternate-token"


def test_gh_cli_token_is_normalized_without_printing_it(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    monkeypatch.delenv("GH_TOKEN", raising=False)
    monkeypatch.setattr(github_auth.shutil, "which", lambda _name: "/usr/bin/gh")
    calls: list[tuple[list[str], dict[str, object]]] = []

    def fake_run(args: list[str], **kwargs: object) -> subprocess.CompletedProcess:
        calls.append((args, kwargs))
        return subprocess.CompletedProcess(args, 0, "cli-token\n", "")

    monkeypatch.setattr(github_auth.subprocess, "run", fake_run)

    assert github_auth.ensure_github_token()
    assert github_auth.os.environ["GITHUB_TOKEN"] == "cli-token"
    assert calls == [
        (
            ["gh", "auth", "token"],
            {
                "stdout": subprocess.PIPE,
                "stderr": subprocess.DEVNULL,
                "text": True,
                "check": False,
            },
        )
    ]


def test_unavailable_credentials_leave_token_unset(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    monkeypatch.delenv("GH_TOKEN", raising=False)
    monkeypatch.setattr(github_auth.shutil, "which", lambda _name: None)

    assert not github_auth.ensure_github_token()
    assert "GITHUB_TOKEN" not in github_auth.os.environ


def test_malformed_cli_output_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    monkeypatch.delenv("GH_TOKEN", raising=False)
    monkeypatch.setattr(github_auth.shutil, "which", lambda _name: "/usr/bin/gh")
    monkeypatch.setattr(
        github_auth.subprocess,
        "run",
        lambda args, **_kwargs: subprocess.CompletedProcess(
            args, 0, "first-token\nsecond-token\n", ""
        ),
    )

    assert not github_auth.ensure_github_token()
    assert "GITHUB_TOKEN" not in github_auth.os.environ
