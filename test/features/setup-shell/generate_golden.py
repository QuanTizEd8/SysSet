#!/usr/bin/env python3
"""Generate (capture) setup-shell golden fixtures by running the real installer.

For each non-failure scenario in scenarios.yaml, this runs `src/setup-shell`'s
installer in a throwaway container with the scenario's options + setup, then
copies every setup-shell-managed file into
`test/features/setup-shell/expected/<scenario>/<full-path>`.

IMPORTANT: fixtures are produced by the same installer the tests exercise, so
they are only meaningful once a human has reviewed the captured tree (and the
diff against the previously-committed fixtures) and confirmed it is correct.
Never commit a regenerated fixture set without reviewing it — see the header of
`checks.yaml`.

Usage:
    python3 test/features/setup-shell/generate_golden.py [--scenario KEY]... [--env ENV]
"""

from __future__ import annotations

import argparse
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

from proman.config import load as load_config
from proman.test.environments import load as load_envs
from proman.test.environments import resolve as resolve_env
from proman.test.scenarios import load as load_scenarios

FEAT = "setup-shell"
HERE = Path(__file__).resolve().parent
EXPECTED = HERE / "expected"
SUPPORT = HERE / "support"


def _stringify(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _option_exports(options: dict) -> str:
    parts = []
    for key, value in (options or {}).items():
        parts.append(f"export {key.upper()}={shlex.quote(_stringify(value))}")
    return "; ".join(parts)


def _capture_scenario(
    name: str, scenario: dict, defaults: dict, image: str, run_in_container: Path
) -> bool:
    # Merge the scenarios.yaml `defaults.options` under the scenario's own
    # options (scenario wins), matching how the test runner resolves them.
    options = {**(defaults.get("options") or {}), **(scenario.get("options") or {})}
    setup = scenario.get("setup") or ""
    out_dir = EXPECTED / name
    # Clear any previous capture on the host (the in-container script cannot rm
    # the bind-mount point), then recreate.
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    exports = _option_exports(options)
    steps = []
    if setup:
        steps.append(setup)
    if exports:
        steps.append(exports)  # own statement(s); persist to the install below
    steps.append(f"sh /repo/src/{FEAT}/install.sh")
    steps.append("GOLDEN_OUT=/out bash /support/golden_capture.sh")
    run_cmd = "\n".join(steps)

    cfg = load_config()
    cmd = [
        "bash",
        str(run_in_container),
        "--image",
        image,
        "--name",
        f"golden-{FEAT}-{name.replace('.', '-')}",
        "--bind",
        f"{cfg.absolute_path('path.src') / FEAT}:/repo/src/{FEAT}:ro",
        "--bind",
        f"{SUPPORT}:/support:ro",
        "--bind",
        f"{out_dir}:/out:rw",
        "--run",
        run_cmd,
    ]
    print(f"\n══ capture golden: {name} [{image}] ══", flush=True)
    result = subprocess.run(cmd, check=False)
    if result.returncode != 0:
        print(f"⛔ capture failed for scenario {name!r}", file=sys.stderr)
        return False
    return True


def main() -> int:
    """Capture golden fixtures for the requested (or all standalone) scenarios."""
    parser = argparse.ArgumentParser(description="Capture setup-shell golden fixtures")
    parser.add_argument(
        "--scenario", action="append", default=[], help="Only these scenario keys"
    )
    parser.add_argument(
        "--env", default="debian-stable", help="Environment key (default debian-stable)"
    )
    args = parser.parse_args()

    cfg = load_config()
    src_install = cfg.absolute_path("path.src") / FEAT / "install.sh"
    if not src_install.is_file():
        print(f"⛔ {src_install} missing — run `just sync-src` first", file=sys.stderr)
        return 1

    run_in_container = cfg.absolute_path("path.test_run_in_container")
    envs = load_envs(cfg.absolute_path("path.test_environments"))
    image = resolve_env(args.env, envs)

    defaults, scenarios = load_scenarios(HERE / "scenarios.yaml")
    only = set(args.scenario)

    ok = True
    for name, scenario in scenarios.items():
        if only and name not in only:
            continue
        if scenario.get("expect_install_failure"):
            print(f"skip {name} (expect_install_failure — nothing to capture)")
            continue
        if "standalone" not in (scenario.get("modes") or []):
            print(f"skip {name} (no standalone mode — capture is standalone-only)")
            continue
        if not _capture_scenario(name, scenario, defaults, image, run_in_container):
            ok = False

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
