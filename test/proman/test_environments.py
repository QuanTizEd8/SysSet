"""Tests for proman.test.environments and test/environments.yaml policy."""

# Test names state their contracts; repeating each as a one-line docstring adds noise.
# ruff: noqa: D103

from __future__ import annotations

import io
import json
import re
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml
from jsonschema import Draft202012Validator
from proman.test import environments as env_module
from proman.test import gen_devcontainer
from proman.test import run as run_module
from proman.test.environments import docker_buildkit_env

REPO_ROOT = Path(__file__).resolve().parents[2]
ENVS_PATH = REPO_ROOT / "test" / "environments.yaml"
ENVS_SCHEMA = json.loads(
    (REPO_ROOT / "test" / "environments.schema.json").read_text(encoding="utf-8")
)

# Base keys must not embed version numbers; pins live in image: fields only.
VERSION_IN_BASE_KEY = re.compile(
    r"^(?:ubuntu|debian|alpine|fedora|rockylinux|opensuse-leap|macos)-\d"
)


def _load_environments() -> dict:
    return yaml.safe_load(ENVS_PATH.read_text(encoding="utf-8"))


def _base_key(env_key: str) -> str:
    return env_key.split("+", 1)[0]


def test_docker_buildkit_env_enables_plain_progress() -> None:
    """Test Docker builds use BuildKit with plain progress."""
    env = docker_buildkit_env({"PATH": "/bin"})
    assert env["PATH"] == "/bin"
    assert env["DOCKER_BUILDKIT"] == "1"
    assert env["BUILDKIT_PROGRESS"] == "plain"


def test_environment_base_keys_have_no_version_numbers() -> None:
    """Semantic env keys must not embed distro version numbers."""
    envs = _load_environments()
    offenders = [key for key in envs if VERSION_IN_BASE_KEY.match(_base_key(key))]
    assert not offenders, f"version-baked base keys: {offenders}"


def test_repository_environments_validate_against_schema() -> None:
    Draft202012Validator(ENVS_SCHEMA).validate(_load_environments())


@pytest.mark.parametrize(
    "build",
    [
        {},
        {"dockerfile": "   \n"},
        {"dockerfile": "true", "runFragmentPath": "fragment.sh"},
        {"runFragmentPath": "/absolute.sh"},
        {"runFragmentPath": "../outside.sh"},
        {"runFragmentPath": "a/../fragment.sh"},
        {"runFragmentPath": "a/./fragment.sh"},
        {"runFragmentPath": "a//fragment.sh"},
        {"runFragmentPath": "a/"},
        {"dockerfile": "true", "resolveAttempts": 0},
        {"dockerfile": "true", "resolveAttempts": 4},
        {"dockerfile": "true", "resolveAttempts": True},
        {"dockerfile": "true", "resolveAttempts": "1"},
    ],
)
def test_environment_schema_rejects_invalid_build_contract(build: dict) -> None:
    validator = Draft202012Validator(ENVS_SCHEMA)
    instance = {
        "base": {"image": "example:test", "attributes": {"os.id": "example"}},
        "layer": {"from": "base", "build": build},
    }
    assert list(validator.iter_errors(instance))


def _collect_env_refs_from_scenarios() -> set[str]:
    refs: set[str] = set()
    for path in (REPO_ROOT / "test").rglob("scenarios.yaml"):
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        for spec in data.values():
            if not isinstance(spec, dict):
                continue
            envs = spec.get("envs")
            if not envs:
                continue
            if isinstance(envs, str):
                refs.add(envs)
            else:
                refs.update(envs)
    lib = yaml.safe_load((REPO_ROOT / "test/lib/scenarios.yaml").read_text()) or {}
    for profiles in lib.values():
        if not isinstance(profiles, dict):
            continue
        for profile in profiles.values():
            if isinstance(profile, dict) and "env" in profile:
                refs.add(profile["env"])
    return refs


def test_scenario_env_refs_exist_in_environments_yaml() -> None:
    """Every env key referenced in scenarios must exist in environments.yaml."""
    envs = _load_environments()
    refs = _collect_env_refs_from_scenarios()
    missing = sorted(ref for ref in refs if ref not in envs)
    assert not missing, f"unknown env keys: {missing}"


def test_resolve_optional_output_spools_build_and_default_still_streams(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Matrix callers can buffer builds without changing existing resolve callers."""
    monkeypatch.setattr(
        env_module,
        "load_config",
        lambda: SimpleNamespace(absolute_path=lambda _key: tmp_path),
    )
    envs = {
        "base": {"image": "ubuntu:test"},
        "prepared": {"from": "base", "build": {"dockerfile": "true"}},
    }
    calls: list[dict[str, object]] = []

    def fake_run(
        cmd: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        calls.append(kwargs)
        if "stdout" in kwargs:
            kwargs["stdout"].write("spooled build\n")
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(env_module, "run_with_retry", fake_run)
    output = io.StringIO()
    assert env_module.resolve("prepared", envs, output=output).endswith(":latest")
    assert output.getvalue() == "spooled build\n"
    assert calls[0]["stdout"] is output
    assert calls[0]["stderr"] is subprocess.STDOUT
    assert calls[0]["attempts"] == 3

    assert env_module.resolve("prepared", envs).endswith(":latest")
    assert "stdout" not in calls[1]
    assert "stderr" not in calls[1]


def test_resolve_uses_explicit_outer_build_attempt_budget(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    monkeypatch.setattr(
        env_module,
        "load_config",
        lambda: SimpleNamespace(absolute_path=lambda _key: tmp_path),
    )
    envs = {
        "base": {"image": "ubuntu:test"},
        "prepared": {
            "from": "base",
            "build": {"dockerfile": "true", "resolveAttempts": 1},
        },
    }
    calls: list[int] = []

    def fake_run(_cmd: list[str], **kwargs: object) -> subprocess.CompletedProcess:
        calls.append(kwargs["attempts"])
        return subprocess.CompletedProcess(_cmd, 0)

    monkeypatch.setattr(env_module, "run_with_retry", fake_run)
    env_module.resolve("prepared", envs)
    assert calls == [1]


def test_run_with_retry_spools_retry_diagnostics_in_order(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Buffered resolution keeps retry notices out of concurrent global output."""
    attempts = iter(
        (
            subprocess.CalledProcessError(1, ["docker", "build"]),
            subprocess.CompletedProcess(["docker", "build"], 0),
        )
    )
    monkeypatch.setattr(env_module, "_try_run", lambda *_args: next(attempts))
    monkeypatch.setattr(env_module.time, "sleep", lambda _delay: None)
    diagnostics = io.StringIO()
    env_module.run_with_retry(
        ["docker", "build", "."],
        attempts=2,
        delay=0,
        output=diagnostics,
    )
    assert "attempt 1/2" in diagnostics.getvalue()


def test_run_with_retry_preserves_every_attempt_output_in_chronological_order(
    tmp_path: Path,
) -> None:
    """Disk spooling contains failed output, its notice, then successful output."""
    counter = tmp_path / "counter"
    command = [
        "sh",
        "-c",
        f'n=$(cat "{counter}" 2>/dev/null || echo 0); n=$((n + 1)); '
        f'printf "%s" "$n" > "{counter}"; echo "attempt-$n"; [ "$n" -eq 2 ]',
    ]
    output_path = tmp_path / "combined.log"
    with output_path.open("w", encoding="utf-8") as output:
        env_module.run_with_retry(
            command,
            attempts=2,
            delay=0,
            output=output,
            stdout=output,
            stderr=subprocess.STDOUT,
            text=True,
        )
    content = output_path.read_text(encoding="utf-8")
    assert content.index("attempt-1") < content.index("attempt 1/2")
    assert content.index("attempt 1/2") < content.index("attempt-2")


def test_run_fragment_is_contained_verbatim_and_generator_safe(tmp_path: Path) -> None:
    """A shell fragment is embedded, never line-stripped or context-dependent."""
    fragment = tmp_path / "fragment.sh"
    content = """env FROM=value
cat <<'INNER'
FROM must remain data
INNER
run() { :; }
run
"""
    fragment.write_text(content, encoding="utf-8")
    envs = {
        "base": {"image": "example:test"},
        "layer": {"from": "base", "build": {"runFragmentPath": "fragment.sh"}},
    }
    base, body, _args = env_module._collect_layers("layer", envs, tmp_path)
    assert base == "example:test"
    assert content in body
    assert "FROM must remain data" in body
    assert "COPY fragment.sh" not in body

    output = tmp_path / "generated"
    output.mkdir()
    gen_devcontainer._build_scenario(
        "case", "layer", {}, "ghcr.io/example/feature", envs, output, tmp_path
    )
    generated = (output / "case.Dockerfile").read_text(encoding="utf-8")
    assert content in generated
    assert "COPY fragment.sh" not in generated


@pytest.mark.parametrize(
    "value",
    [
        "/absolute.sh",
        "../outside.sh",
        "sub/../fragment.sh",
        "sub/./fragment.sh",
        "sub//fragment.sh",
        "sub/",
        "sub\\fragment.sh",
        "space fragment.sh",
        "unicode-λ.sh",
        "line\nfragment.sh",
        ".",
        "missing.sh",
    ],
)
def test_run_fragment_rejects_unsafe_or_missing_paths(
    tmp_path: Path, value: str
) -> None:
    with pytest.raises(ValueError, match="runFragmentPath"):
        env_module._load_run_fragment(tmp_path, value)


def test_run_fragment_rejects_unsupported_file_content(tmp_path: Path) -> None:
    directory = tmp_path / "directory"
    directory.mkdir()
    target = tmp_path / "target.sh"
    target.write_text("true\n", encoding="utf-8")
    link = tmp_path / "link.sh"
    link.symlink_to(target)
    binary = tmp_path / "binary.sh"
    binary.write_bytes(b"\xff")
    crlf = tmp_path / "crlf.sh"
    crlf.write_bytes(b"true\r\n")
    carriage_return = tmp_path / "cr.sh"
    carriage_return.write_bytes(b"printf '\r'\n")
    nul = tmp_path / "nul.sh"
    nul.write_bytes(b"true\0\n")
    for value in ("directory", "link.sh", "binary.sh", "crlf.sh", "cr.sh", "nul.sh"):
        with pytest.raises(ValueError, match="runFragmentPath"):
            env_module._load_run_fragment(tmp_path, value)


def test_run_fragment_preserves_supported_bytes_exactly(tmp_path: Path) -> None:
    raw = b"#!/bin/sh\n\n  printf '%s\\n' \"value\"  \n"
    (tmp_path / "fragment.sh").write_bytes(raw)
    assert env_module._load_run_fragment(tmp_path, "fragment.sh").encode() == raw


def test_run_fragment_chooses_non_colliding_outer_delimiter() -> None:
    content = "DEVFEATS_RUN_FRAGMENT\nDEVFEATS_RUN_FRAGMENT_1\n"
    assert env_module._heredoc_delimiter(content) == "DEVFEATS_RUN_FRAGMENT_2"


def test_inline_commands_use_the_same_non_colliding_delimiter(tmp_path: Path) -> None:
    commands = "printf '%s\\n' data\nDEVFEATS_RUN_FRAGMENT\n"
    envs = {
        "base": {"image": "example:test"},
        "layer": {"from": "base", "build": {"dockerfile": commands}},
    }
    _base, body, _args = env_module._collect_layers("layer", envs, tmp_path)
    assert "RUN <<'DEVFEATS_RUN_FRAGMENT_1'" in body
    assert "\nDEVFEATS_RUN_FRAGMENT\n" in body


def _macos_fragment_envs() -> dict:
    return {
        "mac-base": {"image": "macos-15"},
        "mac": {
            "from": "mac-base",
            "build": {"runFragmentPath": "fragment.sh"},
        },
    }


def test_native_macos_resolver_rejects_run_fragment_instead_of_ignoring_it() -> None:
    assert env_module.is_macos("mac", _macos_fragment_envs())
    with pytest.raises(ValueError, match="unsupported for native macOS"):
        env_module.resolve("mac", _macos_fragment_envs())


def test_explicit_null_image_is_rejected_consistently() -> None:
    envs = {"base": {"image": None}, "child": {"from": "base"}}
    with pytest.raises(ValueError, match="image must be a non-empty string"):
        env_module.is_macos("child", envs)
    with pytest.raises(ValueError, match="image must be a non-empty string"):
        env_module.resolve("child", envs)


def test_resolve_unknown_environment_raises_value_error() -> None:
    with pytest.raises(ValueError, match="Unknown environment"):
        env_module.resolve("missing", {})


def test_devcontainer_generator_validates_macos_before_skipping(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    envs_path = tmp_path / "environments.yaml"
    envs_path.write_text(yaml.safe_dump(_macos_fragment_envs()), encoding="utf-8")
    monkeypatch.setattr(
        gen_devcontainer,
        "load_config",
        lambda: SimpleNamespace(
            root_path=REPO_ROOT,
            absolute_path=lambda _key: tmp_path,
        ),
    )
    scenarios = {"case": {"envs": ["mac"], "modes": ["macos"]}}
    with pytest.raises(ValueError, match="unsupported for native macOS"):
        gen_devcontainer.generate(
            "feature",
            {},
            scenarios,
            envs_path,
            tmp_path / "output",
            checks_data={},
        )


def test_native_macos_runner_validates_fragment_before_execution(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    assert_path = tmp_path / "assert.sh"
    assert_path.write_text("#!/bin/sh\n", encoding="utf-8")
    cfg = SimpleNamespace(
        root_path=REPO_ROOT,
        absolute_path=lambda key: (
            assert_path if key == "path.test_assert" else tmp_path
        ),
    )
    monkeypatch.setattr(run_module, "load_config", lambda: cfg)
    monkeypatch.setattr(run_module, "_save_macos_feature_log", lambda *_args: None)
    entries = [
        {
            "env_is_macos": True,
            "key": "case.mac",
            "env_name": "mac",
            "scenario": {"modes": ["macos"], "tests": []},
        }
    ]
    with pytest.raises(ValueError, match="unsupported for native macOS"):
        run_module._run_macos(
            "feature",
            entries,
            "",
            _macos_fragment_envs(),
            {},
        )


@pytest.mark.parametrize(
    "build",
    [
        [],
        {},
        {"dockerfile": ""},
        {"dockerfile": "   \n"},
        {"dockerfile": "true", "runFragmentPath": "fragment.sh"},
        {"dockerfile": "true", "unknown": 1},
        {"dockerfile": "true", "resolveAttempts": 0},
        {"dockerfile": "true", "resolveAttempts": 4},
        {"dockerfile": "true", "resolveAttempts": True},
        {"dockerfile": "true", "resolveAttempts": "1"},
    ],
)
def test_runtime_rejects_every_schema_invalid_build_shape(build: object) -> None:
    envs = {
        "base": {"image": "example:test"},
        "layer": {"from": "base", "build": build},
    }
    with pytest.raises(ValueError, match="Environment 'layer'"):
        env_module._collect_layers("layer", envs, REPO_ROOT / "test/envs")
