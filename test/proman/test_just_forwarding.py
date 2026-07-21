"""Execution-level regressions for exact justfile argument forwarding."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parents[2]

ONE_PLATFORM = {
    "test-lib": ("ordinary", "lean"),
    "test-lib-integration": ("ordinary", "integration"),
    "test-lib-all": ("ordinary", "all"),
    "test-lib-bootstrap": ("bootstrap", None),
    "test-lib-complete": ("complete", "all"),
}
ALL_PLATFORMS = {
    "test-lib-envs": ("ordinary", "lean"),
    "test-lib-integration-envs": ("ordinary", "integration"),
    "test-lib-all-envs": ("ordinary", "all"),
    "test-lib-bootstrap-envs": ("bootstrap", None),
    "test-lib-complete-envs": ("complete", "all"),
}


def _fake_pixi(tmp_path: Path) -> tuple[dict[str, str], Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    recorder = bin_dir / "pixi"
    recorder.write_text(
        '#!/usr/bin/env bash\nset -euo pipefail\nprintf \'%s\\0\' "$@" > "$ARGV_LOG"\n',
        encoding="utf-8",
    )
    recorder.chmod(0o755)
    argv_log = tmp_path / "argv.bin"
    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}{os.pathsep}{env['PATH']}"
    env["ARGV_LOG"] = str(argv_log)
    return env, argv_log


def _run_just(tmp_path: Path, recipe: str, args: list[str]) -> list[str]:
    env, argv_log = _fake_pixi(tmp_path)
    result = subprocess.run(
        ["just", recipe, *args],
        cwd=REPO_ROOT,
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert result.returncode == 0, result.stdout
    fields = argv_log.read_bytes().split(b"\0")
    assert fields[-1] == b""
    return [field.decode() for field in fields[:-1]]


def _expected(
    recipe: str,
    platform: str = "ubuntu-stable",
    forwarded: list[str] | None = None,
) -> list[str]:
    forwarded = forwarded or []
    one = recipe in ONE_PLATFORM
    workload, tier = (ONE_PLATFORM if one else ALL_PLATFORMS)[recipe]
    task = "test-lib-platform" if one else "test-lib-platforms"
    expected = ["run", "--environment", "test", task]
    if one:
        expected.append(platform)
    expected += ["--workload", workload]
    if tier is not None:
        expected += ["--ordinary-tier", tier]
    return [*expected, "--", *forwarded]


@pytest.mark.parametrize("recipe", [*ONE_PLATFORM, *ALL_PLATFORMS])
def test_zero_arguments_are_forwarded_exactly(tmp_path: Path, recipe: str) -> None:
    """Every public recipe preserves an exact empty runner remainder."""
    assert _run_just(tmp_path, recipe, []) == _expected(recipe)


@pytest.mark.parametrize("recipe", [*ONE_PLATFORM, *ALL_PLATFORMS])
def test_adversarial_arguments_neither_split_expand_nor_execute(
    tmp_path: Path, recipe: str
) -> None:
    """Shell metacharacters survive both just layers without evaluation."""
    marker = tmp_path / "executed"
    forwarded = [
        "space value",
        "apostrophe's",
        "*.definitely-no-match",
        f"$(touch {marker})",
        f"; touch {marker}",
    ]
    one = recipe in ONE_PLATFORM
    args = ["custom-platform", *forwarded] if one else forwarded
    assert _run_just(tmp_path, recipe, args) == _expected(
        recipe,
        platform="custom-platform",
        forwarded=forwarded,
    )
    assert not marker.exists()


def test_linux_workflow_keeps_seven_jobs_and_runs_complete_workload() -> None:
    """Linux CI retains one matrix and delegates complete platform execution."""
    workflow = (REPO_ROOT / ".github/workflows/test-lib.yaml").read_text(
        encoding="utf-8"
    )
    assert (
        "matrix:\n        env: ${{ fromJSON(inputs.config).linux_matrix }}" in workflow
    )
    assert 'just test-lib-complete "${{ matrix.env.name }}"' in workflow
    assert "ordinary_env" not in workflow
    assert "bootstrap_env" not in workflow
