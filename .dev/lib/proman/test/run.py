"""Run devcontainer feature tests in devcontainer, standalone, and macOS modes.

Test layout paths come from ``proman.config.load()`` (``.config/proman/_main.yaml``).
Install logs are written under ``path.local_logs_features`` — see
``docs/source/dev-guide/tests/features.md``.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from proman.config import load as load_config
from proman.feature_env import resolved_env_vars

from .checks import install_failure_patterns
from .codegen import _render_group
from .environments import docker_buildkit_env, resolve
from .environments import load as load_envs
from .feature_logs import (
    DEVFEATS_LOG_BIND_DIR_ENV,
    append_bind_mount_copy_to_test_script,
    container_log_path,
    copy_log_to_bind_mount_fragment,
    ensure_host_log_dir,
    patch_devcontainer_scenario_logging,
)
from .gen_devcontainer import generate
from .loader import FeatureTestError, FeatureTestLoader
from .names import FeatureTestRun, host_log_path
from .scenarios import (
    DEFAULT_MODES,
    LOG_LEVELS,
    apply_log_overrides,
    merge_scenario_env_vars,
    resolve_log_overrides,
)

_SHIM_SETUP = (
    "mkdir -p /tmp/_testlib"
    " && cp /repo/test/support/assert.sh /tmp/_testlib/dev-container-features-test-lib"
    " && chmod +x /tmp/_testlib/dev-container-features-test-lib"
)

_SUDO_STUB = (
    "mkdir -p /tmp/_nosudo"
    r" && printf '#!/bin/sh\nexit 1\n' > /tmp/_nosudo/sudo"
    " && chmod +x /tmp/_nosudo/sudo"
    " && export PATH=/tmp/_nosudo:$PATH"
)

_MACOS_CLEAN_BASE_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

_MACOS_ENV_PASSTHROUGH = frozenset(
    {
        "HOME",
        "USER",
        "LOGNAME",
        "SHELL",
        "TERM",
        "TMPDIR",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "LC_MESSAGES",
        "LC_NUMERIC",
        "LC_TIME",
        "CI",
        "GITHUB_TOKEN",
        "GITHUB_WORKSPACE",
        "XPC_FLAGS",
        "XPC_SERVICE_NAME",
    },
)


def _standalone_install_block(
    feature: str,
    scenario_key: str,
    *,
    expect_install_failure: bool,
    failure_patterns: list[str],
) -> str:
    """Shell fragment: run install once; tee only when validating failure output."""
    install_cmd = f"sh /repo/src/{feature}/install.sh"
    lines: list[str] = []

    if expect_install_failure:
        lines.extend(
            [
                '_FEATURE_INSTALL_LOG="$(mktemp)"',
                '_FEATURE_INSTALL_RC_FILE="$(mktemp)"',
                f"{{ {install_cmd} 2>&1;"
                ' echo $? >"$_FEATURE_INSTALL_RC_FILE"; }'
                ' | tee "$_FEATURE_INSTALL_LOG"',
                'FEATURE_INSTALL_RC="$(cat "$_FEATURE_INSTALL_RC_FILE")"',
                'rm -f "$_FEATURE_INSTALL_RC_FILE"',
            ],
        )
        lines.append(
            'if [ "${FEATURE_INSTALL_RC}" -eq 0 ]; then '
            f'echo "⛔ standalone scenario {scenario_key}: '
            "install unexpectedly succeeded "
            '(expect_install_failure=true)." >&2; '
            "exit 1; fi"
        )
        for pattern in failure_patterns:
            qpat = shlex.quote(pattern)
            lines.append(
                f'if ! grep -Fq {qpat} "${{_FEATURE_INSTALL_LOG}}"; then '
                f'echo "⛔ standalone scenario {scenario_key}: install output missing '
                f'expected message: {pattern!r}" >&2; '
                "exit 1; fi"
            )
        lines.append('rm -f "${_FEATURE_INSTALL_LOG}"')
    else:
        lines.extend(
            [
                install_cmd,
                "FEATURE_INSTALL_RC=$?",
                'if [ "${FEATURE_INSTALL_RC}" -ne 0 ]; then '
                f'echo "⛔ standalone scenario {scenario_key}: '
                "install failed with exit code "
                '${FEATURE_INSTALL_RC}." >&2; '
                "exit ${FEATURE_INSTALL_RC}; fi",
            ],
        )

    return "\n".join(lines)


def _run_install_live(
    install_script: Path,
    env: dict[str, str],
    *,
    accumulate: bool,
) -> tuple[int, str]:
    """Run install.sh live; accumulate output only for failure-pattern validation."""
    if not accumulate:
        result = subprocess.run(
            ["/bin/sh", str(install_script)],
            check=False,
            env=env,
        )
        return result.returncode, ""

    proc = subprocess.Popen(
        ["/bin/sh", str(install_script)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    chunks: list[str] = []
    stdout = proc.stdout
    if stdout is None:
        msg = "install subprocess did not capture stdout"
        raise RuntimeError(msg)
    for line in stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        chunks.append(line)
    return proc.wait(), "".join(chunks)


def _validate_install_failure_output(
    scenario_key: str,
    *,
    mode: str,
    returncode: int,
    output: str,
    failure_patterns: list[str],
) -> str | None:
    """Return an error message when an expected install failure is not satisfied."""
    if returncode == 0:
        return (
            f"{mode} scenario {scenario_key}: install unexpectedly succeeded "
            "(expect_install_failure=true)."
        )
    for pattern in failure_patterns:
        if pattern not in output:
            return (
                f"{mode} scenario {scenario_key}: install output missing expected "
                f"message: {pattern!r}"
            )
    return None


def _run_subprocess_streaming(
    cmd: list[str],
    *,
    env: dict[str, str],
) -> tuple[int, str]:
    """Run a command, streaming stdout/stderr to the terminal while capturing output."""
    proc = subprocess.Popen(
        cmd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    chunks: list[str] = []
    stdout = proc.stdout
    if stdout is None:
        msg = "subprocess did not capture stdout"
        raise RuntimeError(msg)
    for line in stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        chunks.append(line)
    return proc.wait(), "".join(chunks)


def _options_exports(options: dict) -> str:
    lines = []
    for k, v in options.items():
        env_key = k.upper().replace("-", "_")
        val = str(v).lower() if isinstance(v, bool) else str(v)
        lines.append(f"export {env_key}={shlex.quote(val)}")
    return "\n".join(lines)


def _build_macos_base_env(env_name: str, envs: dict) -> dict:
    """Return the env dict used for all macOS subprocess calls in a scenario.

    When clean_path is set on the environment, starts from an allowlist of
    essential variables and replaces PATH with the macOS system baseline plus
    any path_prepend directories declared on the environment. Otherwise returns
    a copy of os.environ (unchanged behaviour for environments without clean_path).
    """
    env_def = envs.get(env_name, {})
    if not env_def.get("clean_path", False):
        base = dict(os.environ)
        base["REPO_ROOT"] = str(load_config().root_path)
        return base
    base = {k: v for k, v in os.environ.items() if k in _MACOS_ENV_PASSTHROUGH}
    prepend = env_def.get("path_prepend", "").strip()
    clean_base = _MACOS_CLEAN_BASE_PATH
    base["PATH"] = f"{prepend}:{clean_base}" if prepend else clean_base
    base["REPO_ROOT"] = str(load_config().root_path)
    return base


def _known_entry_keys(entries: list[dict]) -> set[str]:
    return {entry["key"] for entry in entries}


def _key_matches_filter(key: str, filter_prefix: str, known_keys: set[str]) -> bool:
    """Exact match when filter equals a known key; otherwise prefix match."""
    if not filter_prefix:
        return True
    if filter_prefix in known_keys:
        return key == filter_prefix
    return key.startswith(filter_prefix)


def _devcontainer_keys(
    entries: list[dict],
    filter_prefix: str,
) -> list[str]:
    known_keys = _known_entry_keys(entries)
    keys: list[str] = []
    for entry in entries:
        if entry["env_is_macos"]:
            continue
        key = entry["key"]
        if not _key_matches_filter(key, filter_prefix, known_keys):
            continue
        modes = entry["scenario"].get("modes", list(DEFAULT_MODES))
        if modes == ["standalone"]:
            continue
        if "devcontainer" not in modes:
            continue
        keys.append(key)
    return keys


def _run_devcontainer(
    feature: str,
    filter_prefix: str,
    entries: list[dict],
    checks_data: dict,
    log_overrides: dict[str, str] | None = None,
) -> bool:
    ensure_host_log_dir()
    keys = _devcontainer_keys(entries, filter_prefix)
    if not keys:
        return True

    cfg = load_config()
    log_bind_dir = ensure_host_log_dir()
    feat = cfg.absolute_path("path.test_features") / feature
    success = True
    for key in keys:
        entry = next(e for e in entries if e["key"] == key)
        scenario = entry["scenario"]
        options = scenario.get("options", {})
        expect_install_failure = bool(scenario.get("expect_install_failure", False))
        failure_patterns = install_failure_patterns(
            checks_data,
            scenario.get("tests", []),
        )
        if expect_install_failure and not failure_patterns:
            print(
                f"⛔ devcontainer scenario {key}: expect_install_failure=true but no "
                "install_failure pattern in checks.yaml for tests "
                f"{scenario.get('tests', [])!r}.",
                file=sys.stderr,
            )
            success = False
            continue
        run = FeatureTestRun(feature, key, "devcontainer")

        with tempfile.TemporaryDirectory() as tmpdir_str:
            tmpdir = Path(tmpdir_str)
            (tmpdir / "src").symlink_to(cfg.absolute_path("path.src"))

            test_out_dir = tmpdir / "test" / feature
            generate(
                feature=feature,
                scenarios_path=feat / str(cfg["filename.feature_scenarios"]),
                envs_path=cfg.absolute_path("path.test_environments"),
                out_dir=tmpdir,
                checks_data=checks_data,
                option_overrides=log_overrides,
            )

            scenarios_json_path = test_out_dir / "scenarios.json"
            with scenarios_json_path.open(encoding="utf-8") as f:
                all_scenarios = json.load(f)
            if key not in all_scenarios:
                print(
                    f"⛔ devcontainer scenario {key}: missing from scenarios.json",
                    file=sys.stderr,
                )
                success = False
                continue
            with scenarios_json_path.open("w", encoding="utf-8") as f:
                json.dump({key: all_scenarios[key]}, f, indent=4)
                f.write("\n")

            patch_devcontainer_scenario_logging(
                scenarios_json_path,
                scenario_key=key,
                options=options,
            )
            test_script = test_out_dir / f"{key}.sh"
            if test_script.is_file():
                append_bind_mount_copy_to_test_script(
                    test_script,
                    run,
                    log_path=container_log_path(options),
                )

            print(f"\n══ devcontainer: {key} ══", flush=True)
            run_env = docker_buildkit_env()
            run_env[DEVFEATS_LOG_BIND_DIR_ENV] = str(log_bind_dir)
            devcontainer_cmd = [
                "devcontainer",
                "features",
                "test",
                "--skip-autogenerated",
                "-f",
                feature,
                "--project-folder",
                str(tmpdir),
            ]
            if expect_install_failure:
                returncode, output = _run_subprocess_streaming(
                    devcontainer_cmd,
                    env=run_env,
                )
            else:
                result = subprocess.run(
                    devcontainer_cmd,
                    check=False,
                    env=run_env,
                )
                returncode = result.returncode
                output = ""
            log_out = host_log_path(run)
            if not log_out.is_file() and not (
                expect_install_failure and returncode != 0
            ):
                print(
                    f"⚠ devcontainer scenario {key}: install log not captured at "
                    f"{log_out}",
                    file=sys.stderr,
                )
            if expect_install_failure:
                err = _validate_install_failure_output(
                    key,
                    mode="devcontainer",
                    returncode=returncode,
                    output=output,
                    failure_patterns=failure_patterns,
                )
                if err:
                    print(f"⛔ {err}", file=sys.stderr)
                    success = False
            elif returncode != 0:
                success = False

    return success


def _run_standalone(
    feature: str,
    entries: list[dict],
    filter_prefix: str,
    envs: dict,
    checks_data: dict,
) -> bool:
    cfg = load_config()

    known_keys = _known_entry_keys(entries)
    success = True
    for entry in entries:
        key = entry["key"]
        env_name = entry["env_name"]
        scenario = entry["scenario"]

        if entry["env_is_macos"]:
            continue
        if not _key_matches_filter(key, filter_prefix, known_keys):
            continue

        modes = scenario.get("modes", list(DEFAULT_MODES))
        if "standalone" not in modes:
            continue

        standalone_cfg = scenario.get("standalone", {})
        user = standalone_cfg.get("user", "")
        sudo_ok = standalone_cfg.get("sudo", True)
        network = standalone_cfg.get("network", "")
        skip_install = standalone_cfg.get("skip_install", False)
        expect_install_failure = bool(scenario.get("expect_install_failure", False))
        test_scripts = scenario.get("tests", [])
        failure_patterns = install_failure_patterns(checks_data, test_scripts)
        if expect_install_failure and not failure_patterns:
            print(
                f"⛔ standalone scenario {key}: expect_install_failure=true but no "
                "install_failure pattern in checks.yaml for tests "
                f"{test_scripts!r}.",
                file=sys.stderr,
            )
            success = False
            continue
        options = scenario.get("options", {})
        sc_args = scenario.get("args") or {}
        sc_env_vars = merge_scenario_env_vars(scenario)

        image = resolve(
            env_name,
            envs,
            scenario_args=sc_args or None,
            scenario_env_vars=sc_env_vars or None,
        )

        test_cmd_lines = []
        _feat_env_str = " ".join(
            f"{k}={shlex.quote(v)}" for k, v in resolved_env_vars(feature).items()
        )
        for ts in test_scripts:
            ts_name = f"{ts}.sh"
            ts_path = f"/tmp/{ts_name}"  # noqa: S108 — path is inside the container
            # Render the test script inline so no tests/ dir is needed on disk.
            content = _render_group(ts, checks_data[ts])
            sentinel = f"DEVFEATS_END_{ts.upper().replace('-', '_').replace('.', '_')}"
            heredoc = f"cat > {ts_path} << '{sentinel}'\n{content}{sentinel}"
            test_cmd_lines.append(f"{heredoc}\nchmod +x {ts_path}")
            if user:
                test_cmd_lines.append(
                    f"su {user} -c '"
                    f"{_feat_env_str}"
                    f" PATH=/tmp/_testlib:$PATH"
                    f" REPO_ROOT=/repo FEATURE_INSTALL_RC=$FEATURE_INSTALL_RC"
                    f" {ts_path}'",
                )
            else:
                test_cmd_lines.append(
                    f"{_feat_env_str}"
                    f" PATH=/tmp/_testlib:$PATH REPO_ROOT=/repo"
                    f" FEATURE_INSTALL_RC=$FEATURE_INSTALL_RC {ts_path}",
                )

        parts = [
            _SHIM_SETUP,
            scenario.get("setup", ""),
            _SUDO_STUB if not sudo_ok else "",
            _options_exports(options),
        ]
        if not skip_install:
            parts.append(
                _standalone_install_block(
                    feature,
                    key,
                    expect_install_failure=expect_install_failure,
                    failure_patterns=failure_patterns,
                ),
            )
        else:
            parts.append("FEATURE_INSTALL_RC=0")
            if expect_install_failure:
                parts.append(
                    'echo "⛔ standalone scenario ' + key + ": invalid config "
                    '(skip_install=true with expect_install_failure=true)." >&2; '
                    "exit 1",
                )
        parts.extend(test_cmd_lines)
        run = FeatureTestRun(feature, key, "standalone")
        parts.append(copy_log_to_bind_mount_fragment(run))

        run_cmd = "\n".join(p for p in parts if p)

        log_bind_dir = ensure_host_log_dir()
        container_name = f"standalone-{feature}-{re.sub(r'[.+]', '-', key)}"
        container_cmd = [
            "bash",
            str(cfg.absolute_path("path.test_run_in_container")),
            "--image",
            image,
            "--name",
            container_name,
            "--log-bind-dir",
            str(log_bind_dir),
            "--bind",
            f"{cfg.absolute_path('path.src') / feature}:/repo/src/{feature}:ro",
            "--bind",
            f"{cfg.root_path / 'test' / 'support'}:/repo/test/support:ro",
            "--run",
            run_cmd,
        ]
        if network == "none":
            container_cmd.append("--network-none")

        print(f"\n══ standalone: {key} [{env_name}] ══", flush=True)
        result = subprocess.run(container_cmd, check=False)
        if result.returncode != 0:
            success = False

    return success


def _run_macos(
    feature: str,
    entries: list[dict],
    filter_prefix: str,
    envs: dict,
    checks_data: dict,
) -> bool:
    cfg = load_config()

    shim_dir = tempfile.mkdtemp()
    try:
        shim_path = Path(shim_dir) / "dev-container-features-test-lib"
        shutil.copy(cfg.absolute_path("path.test_assert"), shim_path)
        shim_path.chmod(0o755)

        success = True
        known_keys = _known_entry_keys(entries)
        for entry in entries:
            if not entry["env_is_macos"]:
                continue

            key = entry["key"]
            env_name = entry["env_name"]
            scenario = entry["scenario"]

            if not _key_matches_filter(key, filter_prefix, known_keys):
                continue

            standalone_cfg = scenario.get("standalone", {})
            user = standalone_cfg.get("user", "")
            skip_install = standalone_cfg.get("skip_install", False)
            expect_install_failure = bool(scenario.get("expect_install_failure", False))
            test_scripts = scenario.get("tests", [])
            failure_patterns = install_failure_patterns(checks_data, test_scripts)
            if expect_install_failure and not failure_patterns:
                print(
                    f"⛔ macos scenario {key}: expect_install_failure=true but no "
                    "install_failure pattern in checks.yaml for tests "
                    f"{test_scripts!r}.",
                    file=sys.stderr,
                )
                success = False
                continue
            options = dict(scenario.get("options", {}))

            try:
                # base_env: clean or full runner env, no feature options yet.
                # Mirrors Docker: env-level setup and scenario setup run before
                # feature options are exported, matching standalone mode behaviour.
                base_env = _build_macos_base_env(env_name, envs)

                env_def = envs.get(env_name, {})
                # macOS: `build.dockerfile` is env bootstrap shell (not Docker). Linux
                # envs use it as Dockerfile RUN body via environments.resolve().
                env_build = env_def.get("build", {}).get("dockerfile", "")
                if env_build:
                    subprocess.run(["bash", "-c", env_build], check=True, env=base_env)

                scenario_setup = scenario.get("setup", "")
                if scenario_setup:
                    subprocess.run(
                        ["bash", "-c", scenario_setup],
                        check=True,
                        env=base_env,
                    )

                # run_env adds feature options on top of base_env for the install
                # script and test scripts.
                run_env = dict(base_env)
                run_env.update(merge_scenario_env_vars(scenario))
                for k, v in options.items():
                    env_key = k.upper().replace("-", "_")
                    run_env[env_key] = str(v).lower() if isinstance(v, bool) else str(v)

                print(f"\n══ macos: {key} ══", flush=True)

                install_rc = 0
                if not skip_install:
                    install_script = (
                        cfg.absolute_path("path.src")
                        / feature
                        / str(cfg["filename.feature_install_sh"])
                    )
                    install_rc, install_output = _run_install_live(
                        install_script,
                        run_env,
                        accumulate=expect_install_failure,
                    )
                    if expect_install_failure:
                        err = _validate_install_failure_output(
                            key,
                            mode="macos",
                            returncode=install_rc,
                            output=install_output,
                            failure_patterns=failure_patterns,
                        )
                        if err:
                            print(f"⛔ {err}", file=sys.stderr)
                            success = False
                    elif install_rc != 0:
                        print(
                            f"⛔ macos scenario {key}: install failed with "
                            f"exit code {install_rc}.",
                            file=sys.stderr,
                        )
                        success = False
                        # Preserve previous semantics: when install unexpectedly
                        # fails, skip scenario tests because setup state is not
                        # guaranteed.
                        continue
                elif expect_install_failure:
                    print(
                        f"⛔ macos scenario {key}: invalid config "
                        "(skip_install=true with expect_install_failure=true).",
                        file=sys.stderr,
                    )
                    success = False
                    continue

                # "login" (default): test runs in a login shell so startup
                # files written by the feature (e.g. ~/.bash_profile) are
                # sourced, giving the install user their fully configured PATH.
                # "nonlogin-noninteractive": plain subprocess — use when the
                # scenario specifically tests BASH_ENV or non-login access.
                test_shell = scenario.get("test_shell", "login")

                for ts in test_scripts:
                    ts_name = f"{ts}.sh"
                    # Render script on-the-fly into shim_dir (no tests/ dir needed).
                    tmp_script = Path(shim_dir) / ts_name
                    tmp_script.write_text(
                        _render_group(ts, checks_data[ts]), encoding="utf-8"
                    )
                    tmp_script.chmod(0o755)
                    ts_path = str(tmp_script)
                    test_env = {
                        **run_env,
                        "PATH": f"{shim_dir}:{run_env['PATH']}",
                        "FEATURE_INSTALL_RC": str(install_rc),
                        **resolved_env_vars(feature),
                    }
                    if user:
                        path_q = shlex.quote(test_env["PATH"])
                        root_q = shlex.quote(str(cfg.root_path))
                        ts_q = shlex.quote(ts_path)
                        cmd = f"PATH={path_q} REPO_ROOT={root_q} {ts_q}"
                        result = subprocess.run(
                            ["su", "-l", user, "-c", cmd]
                            if test_shell == "login"
                            else ["su", user, "-c", cmd],
                            check=False,
                            env=test_env,
                        )
                    else:
                        result = subprocess.run(
                            ["bash", "--login", ts_path]
                            if test_shell == "login"
                            else [ts_path],
                            env=test_env,
                            check=False,
                        )
                    if result.returncode != 0:
                        success = False
            finally:
                _save_macos_feature_log(feature, key, options)

        return success
    finally:
        shutil.rmtree(shim_dir)


def _save_macos_feature_log(feature: str, key: str, options: dict) -> None:
    """Copy the scenario install log to the canonical host log for this run."""
    run = FeatureTestRun(feature, key, "macos")
    src = Path(container_log_path(options))
    if not src.is_file():
        return
    dest = host_log_path(run)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)


def main() -> None:
    """Entry point for proman-test-run CLI."""
    parser = argparse.ArgumentParser(
        description="Run devcontainer feature tests (devcontainer, standalone, macOS).",
    )
    parser.add_argument("feature", help="Feature name (e.g. install-pixi)")
    parser.add_argument(
        "--mode",
        default="all",
        choices=["devcontainer", "standalone", "macos", "all"],
        help="Test mode to run (default: all)",
    )
    parser.add_argument(
        "--filter",
        default="",
        metavar="PREFIX",
        help="Run scenarios whose key equals PREFIX or starts with PREFIX",
    )
    parser.add_argument(
        "--log-level",
        default=None,
        choices=LOG_LEVELS,
        help="Override LOG_LEVEL for every scenario in this run (highest precedence).",
    )
    parser.add_argument(
        "--log-file-level",
        default=None,
        choices=LOG_LEVELS,
        help=(
            "Override LOG_FILE_LEVEL for every scenario in this run "
            "(highest precedence)."
        ),
    )
    parser.add_argument(
        "--xtrace",
        action="store_true",
        help=(
            "Shorthand for --log-file-level trace (enables bash xtrace in the "
            "install log)."
        ),
    )
    args = parser.parse_args()

    cfg = load_config()
    os.environ.setdefault("REPO_ROOT", str(cfg.root_path))

    try:
        loader = FeatureTestLoader()
        ft = loader.load(args.feature)
    except (FeatureTestError, FileNotFoundError) as exc:
        print(f"⛔ {exc}", file=sys.stderr)
        sys.exit(1)

    envs = load_envs(cfg.absolute_path("path.test_environments"))
    entries = ft.expand_entries(envs)
    log_overrides = resolve_log_overrides(
        log_level=args.log_level,
        log_file_level=args.log_file_level,
        xtrace=args.xtrace,
    )
    apply_log_overrides(entries, log_overrides)

    filter_prefix: str = args.filter

    if args.mode == "devcontainer":
        ok = _run_devcontainer(
            args.feature,
            filter_prefix,
            entries,
            ft.checks,
            log_overrides,
        )
        sys.exit(0 if ok else 1)

    if args.mode == "standalone":
        ok = _run_standalone(args.feature, entries, filter_prefix, envs, ft.checks)
        sys.exit(0 if ok else 1)

    if args.mode == "macos":
        ok = _run_macos(args.feature, entries, filter_prefix, envs, ft.checks)
        sys.exit(0 if ok else 1)

    rc = 0
    if not _run_devcontainer(
        args.feature,
        filter_prefix,
        entries,
        ft.checks,
        log_overrides,
    ):
        rc = 1
    if not _run_standalone(args.feature, entries, filter_prefix, envs, ft.checks):
        rc = 1
    has_macos = sys.platform == "darwin" or any(e["env_is_macos"] for e in entries)
    if has_macos and not _run_macos(
        args.feature,
        entries,
        filter_prefix,
        envs,
        ft.checks,
    ):
        rc = 1
    sys.exit(rc)
