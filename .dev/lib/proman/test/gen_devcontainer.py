"""Generate devcontainer scenarios.json from unified scenarios.yaml."""

from __future__ import annotations

import argparse
import json
import shlex
import sys
from pathlib import Path

from proman.config import load as load_config
from proman.feature_env import resolved_env_vars

from .codegen import _render_group
from .environments import _DOCKER_GITHUB_ARG_LINES, _collect_layers, is_macos
from .environments import load as load_envs
from .scenarios import (
    DEFAULT_MODES,
    expand_envs,
    iter_merged_scenarios,
    merge_scenario_env_vars,
)
from .scenarios import load as load_scenarios

_TESTLIB_PATH = "/tmp/_devfeats_testlib/dev-container-features-test-lib"  # noqa: S108


def _posix_testlib_block() -> str:
    """Return a POSIX sh heredoc that writes our assert.sh to a known absolute path.

    The official devcontainer CLI injects its own bash-specific test lib (uses
    bash arrays: FAILED=()) into the test container.  Writing our POSIX-
    compatible assert.sh to a fixed path and sourcing it by that absolute path
    overrides the CLI version without modifying PATH (which would break tests
    that inspect PATH ordering).
    """
    assert_sh = (load_config().root_path / "test" / "support" / "assert.sh").read_text(
        encoding="utf-8"
    )
    sentinel = "DEVFEATS_TEST_LIB_END"
    lib_dir = _TESTLIB_PATH.rsplit("/", 1)[0]
    # Ensure the sentinel lands on its own line even if assert.sh loses its
    # trailing newline (heredoc terminator must be the only thing on the line).
    if not assert_sh.endswith("\n"):
        assert_sh += "\n"
    return (
        f"mkdir -p {lib_dir}\n"
        f"cat > {_TESTLIB_PATH} << '{sentinel}'\n"
        f"{assert_sh}"
        f"{sentinel}\n"
        f"chmod +x {_TESTLIB_PATH}\n"
    )


def _render_test_script(
    content: str, dst: Path, feature: str, *, inject_testlib: bool = False
) -> None:
    """Write a rendered test script to dst, prepending metadata-derived env vars."""
    if inject_testlib:
        # Source our POSIX-compatible lib by absolute path so PATH is not
        # modified (modifying PATH breaks tests that inspect PATH ordering).
        content = content.replace(
            ". dev-container-features-test-lib\n",
            f". {_TESTLIB_PATH}\n",
            1,
        )
    lines = content.splitlines(keepends=True)
    insert_at = 1 if lines and lines[0].startswith("#!") else 0
    vars_block = "".join(
        f"export {k}={shlex.quote(v)}\n" for k, v in resolved_env_vars(feature).items()
    )
    if inject_testlib:
        vars_block = _posix_testlib_block() + vars_block
    lines.insert(insert_at, vars_block)
    dst.write_text("".join(lines), encoding="utf-8")
    dst.chmod(dst.stat().st_mode | 0o111)


def _inject_github_token(scenarios: dict) -> None:
    for scenario in scenarios.values():
        if not isinstance(scenario, dict):
            continue
        build = scenario.get("build")
        if build is None:
            scenario["build"] = {"args": {"GITHUB_TOKEN": "${localEnv:GITHUB_TOKEN}"}}
        elif isinstance(build, dict):
            args = build.setdefault("args", {})
            if isinstance(args, dict):
                args.setdefault("GITHUB_TOKEN", "${localEnv:GITHUB_TOKEN}")


def _build_scenario(
    key: str,
    env_name: str,
    scenario: dict,
    feature: str,
    envs: dict,
    out_dir: Path,
    envs_dir: Path,
) -> dict:
    """Build a single scenario dict and write its Dockerfile."""
    sc_args = scenario.get("args") or {}
    sc_env_vars = merge_scenario_env_vars(scenario)

    base_image, body, build_args = _collect_layers(
        env_name,
        envs,
        envs_dir,
        child_args=sc_args or None,
    )

    if sc_env_vars:
        body += "".join(f"ENV {k}={v}\n" for k, v in sc_env_vars.items())

    setup = scenario.get("setup", "").strip()
    if setup:
        body += f"RUN <<'EOF'\nset -eux\n{setup}\nEOF\n"

    df_name = f"{key}.Dockerfile"
    (out_dir / df_name).write_text(
        f"FROM {base_image}\n{_DOCKER_GITHUB_ARG_LINES}{body}",
    )
    result: dict = {
        "build": {
            "dockerfile": df_name,
            "options": ["--progress=plain"],
        },
    }
    if build_args:
        result["build"]["args"] = dict(build_args)

    dc = scenario.get("devcontainer", {})
    if dc.get("remoteUser"):
        result["remoteUser"] = dc["remoteUser"]
    if dc.get("containerUser"):
        result["containerUser"] = dc["containerUser"]
    if dc.get("build", {}).get("args"):
        result.setdefault("build", {}).setdefault("args", {}).update(
            dc["build"]["args"],
        )

    options = scenario.get("options", {})
    result["features"] = {feature: options}

    return result


def generate(
    feature: str,
    scenarios_path: Path | str,
    envs_path: Path | str,
    out_dir: Path | str,
    *,
    checks_data: dict,
    option_overrides: dict[str, str] | None = None,
) -> None:
    """Generate scenarios.json and Dockerfiles for all devcontainer test scenarios."""
    scenarios_path = Path(scenarios_path)
    envs_path = Path(envs_path)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    defaults, scenarios = load_scenarios(scenarios_path)
    cfg = load_config()
    envs = load_envs(envs_path)
    envs_dir = cfg.absolute_path("path.test_envs")
    scenarios_dir = out_dir / "test" / feature
    scenarios_dir.mkdir(parents=True, exist_ok=True)

    output: dict = {}
    for name, sc in iter_merged_scenarios(defaults, scenarios):
        modes: list[str] = sc.get("modes", list(DEFAULT_MODES))

        for key, env_name, scenario in expand_envs(name, sc):
            if is_macos(env_name, envs):
                continue
            if modes == ["standalone"]:
                continue

            entry_scenario = scenario
            if option_overrides:
                entry_scenario = {
                    **scenario,
                    "options": {**scenario.get("options", {}), **option_overrides},
                }

            # Dockerfiles go into a per-scenario subdir so the devcontainer CLI
            # picks them up via its test/{feature}/{key}/ → .devcontainer/ copy.
            scenario_dir = scenarios_dir / key
            scenario_dir.mkdir(parents=True, exist_ok=True)

            output[key] = _build_scenario(
                key,
                env_name,
                entry_scenario,
                feature,
                envs,
                scenario_dir,
                envs_dir,
            )

            tests = scenario.get("tests", [])
            if tests:
                test_id = tests[0]
                content = _render_group(test_id, checks_data[test_id])
                _render_test_script(
                    content,
                    scenarios_dir / f"{key}.sh",
                    feature,
                    inject_testlib=True,
                )

    _inject_github_token(output)
    (scenarios_dir / "scenarios.json").write_text(json.dumps(output, indent=4) + "\n")


def main_cli() -> None:
    """Parse CLI arguments and run scenario generation."""
    parser = argparse.ArgumentParser(
        description="Generate devcontainer scenarios.json from unified scenarios.yaml",
    )
    parser.add_argument("--feature", required=True)
    parser.add_argument("--unified", required=True, type=Path)
    parser.add_argument("--envs", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()
    generate(args.feature, args.unified, args.envs, args.out_dir)


if __name__ == "__main__":
    sys.exit(main_cli() or 0)
