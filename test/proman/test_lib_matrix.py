"""Non-Docker regressions for the dual-profile library test matrix."""

# Test names state their contracts; repeating each as a one-line docstring adds noise.
# ruff: noqa: D103

from __future__ import annotations

import os
import shlex
import signal
import threading
import time
from pathlib import Path
from types import SimpleNamespace
from typing import TYPE_CHECKING

import pytest
import yaml
from proman.cli import test_lib_matrix as cli
from proman.test import lib_matrix as lm
from proman.test.lib_scenarios import LibScenarioError, load_and_validate, validate

if TYPE_CHECKING:
    import subprocess

REPO_ROOT = Path(__file__).parents[2]
PLATFORMS = (
    "ubuntu-stable",
    "debian-stable",
    "fedora-current",
    "rockylinux-current",
    "alpine-current",
    "opensuse-leap-current",
    "archlinux-current",
)


def _platforms(count: int = 7) -> dict[str, dict[str, dict[str, object]]]:
    return {
        f"platform-{index}": {
            "ordinary": {
                "env": f"ordinary-{index}",
                "env_vars": {
                    "DEVFEATS_TEST_TOOL_CACHE": "required",
                    "DEVFEATS_TEST_TOOL_SOURCE_DIR": (
                        "/opt/devfeats/lib-test-tools/bin"
                    ),
                },
            },
            "bootstrap": {
                "env": f"bootstrap-{index}",
                "env_vars": {"DEVFEATS_TEST_TOOL_CACHE": "disabled"},
            },
        }
        for index in range(count)
    }


def _wire(
    monkeypatch: pytest.MonkeyPatch,
    platforms: dict[str, object] | None = None,
    root: Path = Path("/workspace"),
) -> dict[str, object]:
    platform_map = platforms if platforms is not None else _platforms()
    env_names = {
        profile["env"]
        for profiles in platform_map.values()
        if isinstance(profiles, dict)
        for profile in profiles.values()
        if isinstance(profile, dict) and isinstance(profile.get("env"), str)
    }
    envs = {
        name: {
            "image": f"image-{name}",
            "lib_test_profile": "prepared" if name.startswith("ordinary") else "bare",
        }
        for name in env_names
    }
    cfg = SimpleNamespace(
        root_path=root,
        absolute_path=lambda key: root / key.replace(".", "/"),
    )
    monkeypatch.delenv("HOST_REPO_ROOT", raising=False)
    monkeypatch.delenv("LIB_ROOT", raising=False)
    monkeypatch.setattr(lm, "load_config", lambda: cfg)
    monkeypatch.setattr(lm, "load_and_validate", lambda _path, _envs: platform_map)
    monkeypatch.setattr(lm, "load_envs", lambda _path: envs)
    monkeypatch.setattr(lm, "resolve", lambda name, _envs, **_kwargs: f"image-{name}")
    return envs


def _result(
    platform: str, profile_name: str, env_name: str, returncode: int = 0
) -> lm.ProfileResult:
    return lm.ProfileResult(
        platform, profile_name, env_name, returncode, Path("/missing")
    )


def _context(root: str = "/workspace") -> lm.RunnerContext:
    return lm.RunnerContext(root, f"{root}/run-in-container.sh", None, None)


def test_cli_resolves_github_token_before_running_matrix(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    events: list[str] = []
    monkeypatch.setattr(cli, "ensure_github_token", lambda: events.append("token"))
    monkeypatch.setattr(cli, "run", lambda *_args: events.append("run") or 0)
    monkeypatch.setattr(
        cli.sys,
        "argv",
        ["proman-test-lib-matrix", "--platform", "ubuntu-stable"],
    )

    with pytest.raises(SystemExit, match="0"):
        cli.main()

    assert events == ["token", "run"]


def test_repository_has_exact_ordered_dual_profile_mappings() -> None:
    actual = yaml.safe_load(
        (REPO_ROOT / "test/lib/scenarios.yaml").read_text(encoding="utf-8")
    )
    assert tuple(actual) == PLATFORMS
    expected_parents = {
        "ubuntu-stable": "ubuntu-stable",
        "debian-stable": "debian-stable+bash",
        "fedora-current": "fedora-current+bash",
        "rockylinux-current": "rockylinux-current+bash",
        "alpine-current": "alpine-current+bash",
        "opensuse-leap-current": "opensuse-leap-current+bash",
        "archlinux-current": "archlinux-current",
    }
    for name, bare_env in expected_parents.items():
        assert actual[name] == {
            "ordinary": {
                "env": f"{bare_env}+lib-test-tools",
                "env_vars": {
                    "DEVFEATS_TEST_TOOL_CACHE": "required",
                    "DEVFEATS_TEST_TOOL_SOURCE_DIR": (
                        "/opt/devfeats/lib-test-tools/bin"
                    ),
                },
            },
            "bootstrap": {
                "env": bare_env,
                "env_vars": {"DEVFEATS_TEST_TOOL_CACHE": "disabled"},
            },
        }


def test_repository_platform_profiles_validate_against_real_environments() -> None:
    envs = yaml.safe_load(
        (REPO_ROOT / "test/environments.yaml").read_text(encoding="utf-8")
    )
    platforms = load_and_validate(REPO_ROOT / "test/lib/scenarios.yaml", envs)
    assert tuple(platforms) == PLATFORMS


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        ("root", "must be a mapping"),
        ("name", "name .* invalid"),
        ("platform", "must be a mapping"),
        ("missing", "exactly ordinary and bootstrap"),
        ("extra_profile", "unknown profiles"),
        ("profile", "profile .* must be a mapping"),
        ("extra_key", "unknown keys"),
        ("env", "non-empty string"),
        ("unknown_env", "unknown environment"),
        ("env_vars", "map strings to strings"),
    ],
)
def test_shared_validator_rejects_every_malformed_shape(
    mutation: str, message: str
) -> None:
    data: object = _platforms(1)
    envs = {
        "ordinary-0": {"from": "bootstrap-0", "lib_test_profile": "prepared"},
        "bootstrap-0": {"lib_test_profile": "bare"},
    }
    if mutation == "root":
        data = []
    elif mutation == "name":
        data = {"../bad": _platforms(1)["platform-0"]}
    elif mutation == "platform":
        data = {"platform-0": []}
    elif mutation == "missing":
        del data["platform-0"]["bootstrap"]  # type: ignore[index]
    elif mutation == "extra_profile":
        data["platform-0"]["other"] = {}  # type: ignore[index]
    elif mutation == "profile":
        data["platform-0"]["ordinary"] = []  # type: ignore[index]
    elif mutation == "extra_key":
        data["platform-0"]["ordinary"]["tier"] = "lean"  # type: ignore[index]
    elif mutation == "env":
        data["platform-0"]["ordinary"]["env"] = ""  # type: ignore[index]
    elif mutation == "unknown_env":
        data["platform-0"]["ordinary"]["env"] = "missing"  # type: ignore[index]
    else:
        data["platform-0"]["ordinary"]["env_vars"] = {"COUNT": 1}  # type: ignore[index]
    with pytest.raises(LibScenarioError, match=message):
        validate(data, envs)


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        ("swapped", "requires an environment with lib_test_profile"),
        ("same", "requires an environment with lib_test_profile|distinct"),
        ("missing_role", "declares None"),
        ("inherited_role", "declares None"),
        ("missing_cache", "env_vars must map|env_vars must be exactly"),
        ("missing_source", "env_vars must be exactly"),
        ("extra_var", "env_vars must be exactly"),
        ("wrong_cache", "env_vars must be exactly"),
        ("wrong_source", "env_vars must be exactly"),
        ("bootstrap_source", "env_vars must be exactly"),
        ("mismatched_attributes", "identical platform attributes"),
        ("unrelated_profiles", "must derive from"),
    ],
)
def test_validator_enforces_profile_isolation_semantics(
    mutation: str, message: str
) -> None:
    data = _platforms(1)
    envs: dict[str, object] = {
        "ordinary-0": {"from": "bootstrap-0", "lib_test_profile": "prepared"},
        "bootstrap-0": {"lib_test_profile": "bare"},
    }
    if mutation == "swapped":
        data["platform-0"]["ordinary"]["env"] = "bootstrap-0"
        data["platform-0"]["bootstrap"]["env"] = "ordinary-0"
    elif mutation == "same":
        data["platform-0"]["bootstrap"]["env"] = "ordinary-0"
    elif mutation == "missing_role":
        envs["ordinary-0"] = {}
    elif mutation == "inherited_role":
        envs["parent"] = {"lib_test_profile": "prepared"}
        envs["ordinary-0"] = {"from": "parent"}
    elif mutation == "missing_cache":
        del data["platform-0"]["ordinary"]["env_vars"]
    elif mutation == "missing_source":
        del data["platform-0"]["ordinary"]["env_vars"]["DEVFEATS_TEST_TOOL_SOURCE_DIR"]
    elif mutation == "extra_var":
        data["platform-0"]["ordinary"]["env_vars"]["EXTRA"] = "value"
    elif mutation == "wrong_cache":
        data["platform-0"]["ordinary"]["env_vars"]["DEVFEATS_TEST_TOOL_CACHE"] = (
            "disabled"
        )
    elif mutation == "wrong_source":
        data["platform-0"]["ordinary"]["env_vars"]["DEVFEATS_TEST_TOOL_SOURCE_DIR"] = (
            "/var/empty/untrusted"
        )
    elif mutation == "mismatched_attributes":
        envs["ordinary-0"]["attributes"] = {"os.id": "ubuntu"}  # type: ignore[index]
        envs["bootstrap-0"]["attributes"] = {"os.id": "debian"}  # type: ignore[index]
    elif mutation == "unrelated_profiles":
        del envs["ordinary-0"]["from"]  # type: ignore[index]
    else:
        data["platform-0"]["bootstrap"]["env_vars"]["DEVFEATS_TEST_TOOL_SOURCE_DIR"] = (
            "/opt/devfeats/lib-test-tools/bin"
        )
    with pytest.raises(LibScenarioError, match=message):
        validate(data, envs)


@pytest.mark.parametrize(
    "content",
    ["", "null\n", "[]\n", "scalar\n", "{}\n", "defaults: {}\n", "broken: [\n"],
)
def test_shared_raw_loader_rejects_invalid_yaml_roots(
    tmp_path: Path, content: str
) -> None:
    path = tmp_path / "scenarios.yaml"
    path.write_text(content, encoding="utf-8")
    with pytest.raises(LibScenarioError):
        load_and_validate(path, {})


@pytest.mark.parametrize("tier", ["lean", "integration", "all"])
def test_every_ordinary_tier_runs_all_seven_prepared_profiles(
    monkeypatch: pytest.MonkeyPatch, tier: str
) -> None:
    _wire(monkeypatch)
    calls: list[tuple[str, str, str]] = []

    def fake_run(
        platform: str, profile_name: str, profile: dict, selected: str, *_: object
    ) -> lm.ProfileResult:
        calls.append((platform, profile_name, selected))
        return _result(platform, profile_name, profile["env"])

    monkeypatch.setattr(lm, "_run_profile", fake_run)
    assert lm.run(None, "ordinary", tier, 3, []) == 0
    assert len(calls) == 7
    assert {profile for _, profile, _ in calls} == {"ordinary"}
    assert {selected for _, _, selected in calls} == {tier}


def test_bootstrap_runs_all_seven_bare_profiles(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _wire(monkeypatch)
    calls: list[tuple[str, str]] = []

    def fake_run(
        platform: str, profile_name: str, profile: dict, *_: object
    ) -> lm.ProfileResult:
        calls.append((profile_name, profile["env"]))
        return _result(platform, profile_name, profile["env"])

    monkeypatch.setattr(lm, "_run_profile", fake_run)
    assert lm.run(None, "bootstrap", "lean", 3, []) == 0
    assert sorted(calls) == [("bootstrap", f"bootstrap-{i}") for i in range(7)]


def test_complete_runs_bootstrap_after_ordinary_failure_and_aggregates(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    _wire(monkeypatch, _platforms(1))
    calls: list[str] = []

    def fake_run(
        platform: str, profile_name: str, profile: dict, *_: object
    ) -> lm.ProfileResult:
        calls.append(profile_name)
        rc = 7 if profile_name == "ordinary" else 0
        return _result(platform, profile_name, profile["env"], rc)

    monkeypatch.setattr(lm, "_run_profile", fake_run)
    assert lm.run(None, "complete", "all", 1, []) == 1
    assert calls == ["ordinary", "bootstrap"]
    output = capsys.readouterr().out
    assert output.index("platform-0/ordinary") < output.index("platform-0/bootstrap")


def test_complete_continues_after_ordinary_resolution_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _wire(monkeypatch, _platforms(1))
    resolved: list[str] = []
    ran: list[str] = []

    def fake_resolve(name: str, _envs: dict, **_kwargs: object) -> str:
        resolved.append(name)
        if name.startswith("ordinary"):
            message = "build failed"
            raise RuntimeError(message)
        return "bare-image"

    monkeypatch.setattr(lm, "resolve", fake_resolve)
    monkeypatch.setattr(
        lm,
        "_run_profile",
        lambda platform, profile_name, profile, *_: (
            ran.append(profile_name) or _result(platform, profile_name, profile["env"])
        ),
    )
    assert lm.run(None, "complete", "all", 1, []) == 1
    assert resolved == ["ordinary-0", "bootstrap-0"]
    assert ran == ["bootstrap"]


def test_platform_concurrency_is_bounded_and_profiles_never_overlap(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _wire(monkeypatch)
    lock = threading.Lock()
    active_platforms: set[str] = set()
    maximum = 0

    def fake_run(
        platform: str, profile_name: str, profile: dict, *_: object
    ) -> lm.ProfileResult:
        nonlocal maximum
        with lock:
            assert platform not in active_platforms
            active_platforms.add(platform)
            maximum = max(maximum, len(active_platforms))
        time.sleep(0.01)
        with lock:
            active_platforms.remove(platform)
        return _result(platform, profile_name, profile["env"])

    monkeypatch.setattr(lm, "_run_profile", fake_run)
    assert lm.run(None, "complete", "all", 2, []) == 0
    assert maximum == 2


def test_commands_select_profile_env_vars_tier_and_exact_bootstrap_path() -> None:
    ordinary = {
        "env": "prepared",
        "env_vars": {
            "DEVFEATS_TEST_TOOL_CACHE": "required",
            "DEVFEATS_TEST_TOOL_SOURCE_DIR": "/opt/devfeats/lib-test-tools/bin",
        },
    }
    bootstrap = {
        "env": "bare",
        "env_vars": {"DEVFEATS_TEST_TOOL_CACHE": "disabled"},
    }
    ordinary_cmd = lm._build_profile_command(
        "ubuntu",
        "ordinary",
        ordinary,
        "integration",
        "image",
        ["--filter", "a b"],
        "token",
        _context(),
    )
    bootstrap_cmd = lm._build_profile_command(
        "ubuntu",
        "bootstrap",
        bootstrap,
        "all",
        "image",
        ["--filter", "a b"],
        "token",
        _context(),
    )
    ordinary_run = shlex.split(ordinary_cmd[ordinary_cmd.index("--run") + 1])
    bootstrap_run = shlex.split(bootstrap_cmd[bootstrap_cmd.index("--run") + 1])
    assert ordinary_run[-4:] == ["--tier", "integration", "--filter", "a b"]
    assert bootstrap_run[-4:] == [
        "--path",
        "/repo/test/lib/bootstrap/bootstrap.bats",
        "--filter",
        "a b",
    ]
    assert "DEVFEATS_TEST_TOOL_CACHE=required" in ordinary_cmd
    assert (
        "DEVFEATS_TEST_TOOL_SOURCE_DIR=/opt/devfeats/lib-test-tools/bin" in ordinary_cmd
    )
    assert "DEVFEATS_TEST_TOOL_CACHE=disabled" in bootstrap_cmd
    assert not any("DEVFEATS_TEST_TOOL_SOURCE_DIR=" in arg for arg in bootstrap_cmd)
    assert ordinary_cmd[ordinary_cmd.index("--name") + 1].endswith("-ubuntu-ordinary")
    assert bootstrap_cmd[bootstrap_cmd.index("--name") + 1].endswith(
        "-ubuntu-bootstrap"
    )


@pytest.mark.parametrize(
    ("workload", "args"),
    [
        ("ordinary", ["--tier", "all"]),
        ("ordinary", ["--tier=all"]),
        ("ordinary", ["--path", "test/lib/bootstrap/bootstrap.bats"]),
        ("ordinary", ["--path=test/lib/bootstrap/bootstrap.bats"]),
        ("ordinary", ["-h"]),
        ("ordinary", ["--help"]),
        ("ordinary", ["--list-files"]),
        ("ordinary", ["--clean-path"]),
        ("ordinary", ["--path-prepend=/tmp/tools"]),
        ("ordinary", ["--module=os"]),
        ("ordinary", ["--jobs=2"]),
        ("complete", ["--path", "test/lib/os.bats"]),
        ("bootstrap", ["--module", "os"]),
        ("complete", ["--jobs", "2"]),
        ("bootstrap", ["--path-prepend", "/prepared/tools"]),
        ("complete", ["--clean-path"]),
    ],
)
def test_matrix_owned_runner_options_are_rejected_before_config(
    monkeypatch: pytest.MonkeyPatch, workload: str, args: list[str]
) -> None:
    monkeypatch.setattr(lm, "load_config", lambda: pytest.fail("config loaded"))
    assert lm.run(None, workload, "all", 3, args) == 2


@pytest.mark.parametrize(
    "args",
    [
        ["--future-early-success"],
        ["stray-value"],
        ["--filter"],
        ["--filter="],
        ["--filter", "--help"],
    ],
)
def test_forwarded_argument_allowlist_rejects_unknown_or_incomplete_grammar(
    monkeypatch: pytest.MonkeyPatch, args: list[str]
) -> None:
    monkeypatch.setattr(lm, "load_config", lambda: pytest.fail("config loaded"))
    assert lm.run(None, "ordinary", "lean", 1, args) == 2


def test_ordinary_forwarding_allowlist_keeps_supported_selection_options() -> None:
    assert not lm._validate_options(
        "ordinary",
        "lean",
        1,
        ["--filter=network", "--module", "net", "--jobs", "2"],
    )


def test_top_level_interrupt_stops_process_tree_and_cleans_exact_resources(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    _wire(monkeypatch, _platforms(1), root=tmp_path)
    runner = tmp_path / "runner.sh"
    marker = tmp_path / "runner-started"
    child_pid_path = tmp_path / "child.pid"
    launches = tmp_path / "launches"
    runner.write_text(
        "#!/bin/sh\n"
        'printf \'%s\\n\' "$*" >> "$LAUNCHES"\n'
        "sleep 60 &\n"
        'printf \'%s\\n\' "$!" > "$CHILD_PID_PATH"\n'
        'printf ready > "$RUNNER_MARKER"\n'
        "wait\n",
        encoding="utf-8",
    )
    runner.chmod(0o755)
    monkeypatch.setenv("CHILD_PID_PATH", str(child_pid_path))
    monkeypatch.setenv("RUNNER_MARKER", str(marker))
    monkeypatch.setenv("LAUNCHES", str(launches))
    monkeypatch.setattr(
        lm,
        "_runner_context",
        lambda: (lm.RunnerContext(str(tmp_path), str(runner), None, None), ""),
    )
    logs_dir = tmp_path / "matrix-logs"
    logs_dir.mkdir()
    monkeypatch.setattr(lm.tempfile, "mkdtemp", lambda **_kwargs: str(logs_dir))
    cleanup_calls: list[tuple[str, ...]] = []

    def track_cleanup(names: tuple[str, ...]) -> None:
        cleanup_calls.append(names)

    monkeypatch.setattr(
        lm.ProcessRegistry,
        "_remove_containers",
        staticmethod(track_cleanup),
    )
    registered = threading.Event()
    original_add = lm.ProcessRegistry.add

    def track_registration(
        registry: lm.ProcessRegistry,
        process: subprocess.Popen[str],
    ) -> None:
        original_add(registry, process)
        registered.set()

    monkeypatch.setattr(lm.ProcessRegistry, "add", track_registration)

    def interrupt_after_launch() -> None:
        deadline = time.monotonic() + 2
        while (
            not marker.exists() or not registered.is_set()
        ) and time.monotonic() < deadline:
            time.sleep(0.01)
        os.kill(os.getpid(), signal.SIGINT)

    interrupter = threading.Thread(target=interrupt_after_launch)
    interrupter.start()
    started = time.monotonic()
    assert lm.run(None, "complete", "lean", 1, []) == 130
    interrupter.join(timeout=1)
    assert not interrupter.is_alive()
    assert marker.exists()
    assert time.monotonic() - started < 5
    assert not logs_dir.exists()
    assert len(cleanup_calls) == 2
    assert cleanup_calls[0] == cleanup_calls[1]
    assert len(cleanup_calls[0]) == 1
    assert cleanup_calls[0][0].startswith("test-lib-")
    assert cleanup_calls[0][0].endswith("-platform-0-ordinary")
    launch_lines = launches.read_text(encoding="utf-8").splitlines()
    assert len(launch_lines) == 1
    assert "-platform-0-ordinary" in launch_lines[0]
    assert "-platform-0-bootstrap" not in launch_lines[0]
    output = capsys.readouterr().out
    assert "platform-0/ordinary: CANCELLED (130)" in output
    assert "platform-0/bootstrap: CANCELLED (130)" in output
    assert output.index("platform-0/ordinary:") < output.index("platform-0/bootstrap:")
    child_pid = int(child_pid_path.read_text(encoding="utf-8"))
    with pytest.raises(ProcessLookupError):
        os.kill(child_pid, 0)


def test_worker_crash_synthesizes_both_complete_profile_results(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    _wire(monkeypatch, _platforms(1))
    monkeypatch.setattr(
        lm, "_run_platform", lambda *_: (_ for _ in ()).throw(RuntimeError("boom"))
    )
    assert lm.run(None, "complete", "all", 1, []) == 1
    output = capsys.readouterr().out
    assert "platform-0/ordinary: FAIL" in output
    assert "platform-0/bootstrap: FAIL" in output


def test_resolution_does_not_swallow_keyboard_interrupt(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    _wire(monkeypatch, _platforms(1))
    monkeypatch.setattr(
        lm,
        "resolve",
        lambda *_, **_kwargs: (_ for _ in ()).throw(KeyboardInterrupt()),
    )
    with pytest.raises(KeyboardInterrupt):
        lm._run_platform(
            "platform-0",
            _platforms(1)["platform-0"],
            "ordinary",
            "lean",
            [],
            "token",
            _context(),
            {},
            tmp_path,
            threading.Event(),
            lm.ProcessRegistry(threading.Event()),
        )


def test_ci_artifact_bind_is_preserved_for_profiles(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _wire(monkeypatch, root=Path("/repo"))
    context = lm.RunnerContext(
        "/host",
        "/repo/run-in-container.sh",
        "/repo/dist/lib-test",
        "/host/dist/lib-test:/repo/dist/lib-test:ro",
    )
    cmd = lm._build_profile_command(
        "platform-0",
        "bootstrap",
        _platforms(1)["platform-0"]["bootstrap"],
        "all",
        "image",
        [],
        "token",
        context,
    )
    assert context.lib_bind in cmd
    assert "LIB_ROOT=/repo/dist/lib-test" in cmd


def test_cli_separator_and_new_options_are_forwarded_exactly(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[tuple[object, ...]] = []
    monkeypatch.setattr(cli, "run", lambda *args: calls.append(args) or 0)
    monkeypatch.setattr(
        cli.sys,
        "argv",
        [
            "matrix",
            "--platform",
            "platform-0",
            "--workload",
            "complete",
            "--ordinary-tier",
            "all",
            "--matrix-jobs",
            "2",
            "--",
            "--filter",
            "space value",
        ],
    )
    with pytest.raises(SystemExit) as exc:
        cli.main()
    assert exc.value.code == 0
    assert calls == [("platform-0", "complete", "all", 2, ["--filter", "space value"])]


@pytest.mark.parametrize(
    "value",
    [
        "0",
        "-1",
        "text",
        "1+1",
        "1" * 10_000,
        "\N{ARABIC-INDIC DIGIT ONE}",
        "$(id)",
    ],
)
def test_cli_rejects_invalid_matrix_jobs(
    monkeypatch: pytest.MonkeyPatch, value: str
) -> None:
    monkeypatch.setattr(cli.sys, "argv", ["matrix", "--matrix-jobs", value])
    with pytest.raises(SystemExit) as exc:
        cli.main()
    assert exc.value.code == 2


def test_prepared_environment_declarations_and_installer_are_immutable() -> None:
    envs = yaml.safe_load((REPO_ROOT / "test/environments.yaml").read_text())
    for platform in yaml.safe_load(
        (REPO_ROOT / "test/lib/scenarios.yaml").read_text()
    ).values():
        prepared = envs[platform["ordinary"]["env"]]
        assert prepared["build"] == {
            "runFragmentPath": "install-lib-test-tools.sh",
            "resolveAttempts": 1,
        }
    installer = (REPO_ROOT / "test/envs/install-lib-test-tools.sh").read_text()
    assert "JQ_VERSION=1.8.2" in installer
    assert "YQ_VERSION=4.53.2" in installer
    assert "JSONSCHEMA_VERSION=16.2.0" in installer
    assert "ORAS_VERSION=1.3.2" in installer
    assert installer.index("verify_checksum") < installer.index("unzip -q")
    assert "/opt/devfeats/lib-test-tools/bin" in installer
    assert "PATH=" not in installer


def test_profile_result_metadata_never_retains_large_output(
    tmp_path: Path,
) -> None:
    runner = tmp_path / "runner.sh"
    runner.write_text(
        "#!/bin/sh\ndd if=/dev/zero bs=1048576 count=2 2>/dev/null\n",
        encoding="utf-8",
    )
    runner.chmod(0o755)
    log_path = tmp_path / "profile.log"
    event = threading.Event()
    result = lm._run_profile(
        "platform",
        "ordinary",
        {
            "env": "prepared",
            "env_vars": {
                "DEVFEATS_TEST_TOOL_CACHE": "required",
                "DEVFEATS_TEST_TOOL_SOURCE_DIR": ("/opt/devfeats/lib-test-tools/bin"),
            },
        },
        "lean",
        "image",
        [],
        "token",
        lm.RunnerContext(str(tmp_path), str(runner), None, None),
        log_path,
        event,
        lm.ProcessRegistry(event),
    )
    assert result.returncode == 0
    assert result.log_path.stat().st_size == 2 * 1024 * 1024
    assert not hasattr(result, "output")


def test_profile_cancellation_terminates_child_process_group(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    runner = tmp_path / "runner.sh"
    grandchild_pid = tmp_path / "grandchild.pid"
    runner.write_text(
        '#!/bin/sh\nsleep 60 &\nprintf \'%s\\n\' "$!" > "$PID_FILE"\nwait\n',
        encoding="utf-8",
    )
    runner.chmod(0o755)
    monkeypatch.setenv("PID_FILE", str(grandchild_pid))
    event = threading.Event()
    registry = lm.ProcessRegistry(event)
    result: list[lm.ProfileResult] = []

    def invoke() -> None:
        result.append(
            lm._run_profile(
                "platform",
                "ordinary",
                {
                    "env": "prepared",
                    "env_vars": {
                        "DEVFEATS_TEST_TOOL_CACHE": "required",
                        "DEVFEATS_TEST_TOOL_SOURCE_DIR": (
                            "/opt/devfeats/lib-test-tools/bin"
                        ),
                    },
                },
                "lean",
                "image",
                [],
                "token",
                lm.RunnerContext(str(tmp_path), str(runner), None, None),
                tmp_path / "cancel.log",
                event,
                registry,
            )
        )

    thread = threading.Thread(target=invoke)
    thread.start()
    deadline = time.monotonic() + 2
    while not grandchild_pid.exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    assert grandchild_pid.exists()
    pid = int(grandchild_pid.read_text(encoding="utf-8"))
    started = time.monotonic()
    event.set()
    registry.terminate_all()
    thread.join(timeout=2)
    assert not thread.is_alive()
    assert time.monotonic() - started < 2
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)
