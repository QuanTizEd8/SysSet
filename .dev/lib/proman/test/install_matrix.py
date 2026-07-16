"""Orchestrate install framework tests across container environments."""

from __future__ import annotations

import os
import shlex
import subprocess
import sys
from pathlib import Path

from proman.config import load as load_config

from .environments import load as load_envs
from .environments import resolve
from .scenarios import expand_test_files
from .scenarios import load as load_scenarios


def _run_env(
    name: str,
    scenario: dict,
    envs: dict,
    extra_args: list[str],
) -> bool:
    """Run install framework tests for one environment; return True on success."""
    env_name = scenario["env"]
    env_vars = scenario.get("env_vars", {})
    cfg = load_config()
    root = cfg.root_path
    # In CI the process runs inside a container where root may be /repo, but
    # Docker bind-mount host paths must resolve on the actual runner host.
    host_root = os.environ.get("HOST_REPO_ROOT", str(root))
    install_dir = cfg.absolute_path("path.test_install")
    test_files = expand_test_files(scenario.get("tests"), install_dir)
    run_in_container = cfg.absolute_path("path.test_run_in_container")

    image = resolve(env_name, envs)

    print(f"\n══ {name} [{env_name}] ══", flush=True)

    cmd = [
        "bash",
        str(run_in_container),
        "--image",
        image,
        "--name",
        f"test-install-{name}",
        "--bind",
        f"{host_root}/lib:/repo/lib:ro",
        "--bind",
        f"{host_root}/test/lib:/repo/test/lib:ro",
        "--bind",
        f"{host_root}/test/install:/repo/test/install:ro",
        "--bind",
        f"{host_root}/src/install-jq:/repo/src/install-jq:ro",
        # texlive_mirror_probe.bats sources the install-texlive feature hook
        # directly (self-contained unit test — the install-jq fixture is the
        # only synced src/ this container binds), so mount that one source file.
        "--bind",
        f"{host_root}/features/install-texlive/install.bash"
        ":/repo/features/install-texlive/install.bash:ro",
        "--bind",
        f"{host_root}/.dev/scripts/test:/repo/.dev/scripts/test:ro",
    ]
    for k, v in env_vars.items():
        cmd += ["--env", f"{k}={v}"]

    run_install_parts: list[str] = ["bash", "/repo/.dev/scripts/test/run-install.sh"]
    for tf in test_files:
        rel = Path(tf).relative_to(root)
        run_install_parts += ["--paths", f"/repo/{rel}"]
    run_install_parts += extra_args

    cmd += ["--run", " ".join(shlex.quote(p) for p in run_install_parts)]

    result = subprocess.run(cmd, check=False)
    return result.returncode == 0


def run(target_env: str | None, extra_args: list[str]) -> int:
    """Run install framework tests for one or all environments; return exit code."""
    cfg = load_config()
    _, scenarios = load_scenarios(cfg.absolute_path("path.test_install_scenarios"))
    envs = load_envs(cfg.absolute_path("path.test_environments"))

    if target_env is not None:
        if target_env not in scenarios:
            print(f"⛔ Unknown environment: {target_env!r}", file=sys.stderr)
            return 1
        ok = _run_env(
            target_env,
            scenarios[target_env],
            envs,
            extra_args,
        )
        return 0 if ok else 1

    passed = failed = 0
    for name, scenario in scenarios.items():
        if _run_env(name, scenario, envs, extra_args):
            passed += 1
        else:
            failed += 1

    print(f"\nMatrix: {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1
