"""Behavioral and policy tests for BATS suite-scoped external tools."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SETUP_SUITE = REPO_ROOT / "test/lib/setup_suite.bash"
HELPER = REPO_ROOT / "test/lib/helpers/test_tools.bash"


def _fake_tool(directory: Path, name: str, *, compatible: bool = True) -> Path:
    path = directory / name
    if name == "jq":
        body = """
if [[ "$1" == --version ]]; then printf 'jq-%s\\n' "${FAKE_VERSION:-1.8.2}"; exit 0; fi
while IFS= read -r line; do :; done
printf '42\\n'
""" % ("1.8.2" if compatible else "0.1")
    elif name == "yq":
        version = "4.53.2" if compatible else "3.4.1"
        body = f"""
if [[ "$1" == --version ]]; then
  printf 'yq (https://github.com/mikefarah/yq/) version v{version}\\n'; exit 0
fi
while IFS= read -r line; do :; done
printf '42\\n'
"""
    elif name == "jsonschema":
        version = "16.0.0" if compatible else "python-jsonschema"
        body = f"""
if [[ "$1" == version ]]; then printf '{version}\\n'; exit 0; fi
[[ "$1" == validate && -f "$2" && -f "$3" ]]
"""
    else:
        version = "1.3.0" if compatible else "0.9.0"
        body = f"printf 'Version: {version}\\nGo version: go1.30.0\\n'\n"
    path.write_text(f"#!/usr/bin/env bash\n{body}", encoding="utf-8")
    path.chmod(0o755)
    return path


@pytest.fixture
def tool_source(tmp_path: Path) -> Path:
    """Create a complete compatible prepared-tool source directory."""
    source = tmp_path / "source tools"
    source.mkdir()
    for name in ("jq", "yq", "jsonschema", "oras"):
        _fake_tool(source, name)
    return source


def _run_setup(
    tmp_path: Path,
    *,
    mode: str,
    source: Path | None = None,
    required: str = "jq yq jsonschema oras",
    path: str | None = None,
    after: str = "env",
) -> subprocess.CompletedProcess[str]:
    suite_tmp = tmp_path / "suite tmp"
    suite_tmp.mkdir(exist_ok=True)
    env = {
        **os.environ,
        "DEVFEATS_TEST_TOOL_CACHE": mode,
        "DEVFEATS_TEST_REQUIRED_TOOLS": required,
        "BATS_SUITE_TMPDIR": str(suite_tmp),
    }
    if source is not None:
        env["DEVFEATS_TEST_TOOL_SOURCE_DIR"] = str(source)
    else:
        env.pop("DEVFEATS_TEST_TOOL_SOURCE_DIR", None)
    if path is not None:
        env["PATH"] = path
    script = f'source "$1"; setup_suite || exit $?; {after}'
    return subprocess.run(
        ["bash", "-c", script, "_", str(SETUP_SUITE)],
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def test_required_source_with_spaces_copies_and_exports_all_tools(
    tmp_path: Path, tool_source: Path
) -> None:
    """An explicit prepared bundle is fully validated and privately copied."""
    result = _run_setup(
        tmp_path,
        mode="required",
        source=tool_source,
        after="printf '%s\\n' \"$DEVFEATS_TEST_TOOLS_DIR\" "
        '"$DEVFEATS_TEST_JQ_BIN" "$DEVFEATS_TEST_YQ_BIN" '
        '"$DEVFEATS_TEST_JSONSCHEMA_BIN" "$DEVFEATS_TEST_ORAS_BIN"',
    )
    assert result.returncode == 0, result.stderr
    paths = [Path(line) for line in result.stdout.splitlines()]
    assert len(paths) == 5
    assert paths[0].name == "tools"
    assert paths[0].stat().st_mode & 0o777 == 0o555
    for path in paths[1:]:
        assert path.parent == paths[0]
        assert path.is_file()
        assert not path.is_symlink()
        assert path.stat().st_mode & 0o777 == 0o555


def test_suite_copy_is_unchanged_when_source_is_mutated(
    tmp_path: Path, tool_source: Path
) -> None:
    """The suite uses copies, not mutable references back to prepared sources."""
    result = _run_setup(
        tmp_path,
        mode="required",
        source=tool_source,
        after='printf "%s\\n" "$DEVFEATS_TEST_JQ_BIN"',
    )
    assert result.returncode == 0, result.stderr
    cached = Path(result.stdout.strip())
    before = cached.read_bytes()
    (tool_source / "jq").write_text("corrupted\n", encoding="utf-8")
    assert cached.read_bytes() == before


def test_teardown_reopens_cache_directory_for_bats_cleanup(
    tmp_path: Path, tool_source: Path
) -> None:
    """The cache is immutable during tests but removable after teardown."""
    result = _run_setup(
        tmp_path,
        mode="required",
        source=tool_source,
        after='teardown_suite || exit $?; printf "%s\\n" "$DEVFEATS_TEST_TOOLS_DIR"',
    )
    assert result.returncode == 0, result.stderr
    tools_dir = Path(result.stdout.strip())
    assert tools_dir.stat().st_mode & 0o777 == 0o700
    for name in ("jq", "yq", "jsonschema", "oras"):
        assert (tools_dir / name).stat().st_mode & 0o777 == 0o555


@pytest.mark.parametrize("problem", ["missing", "symlink"])
def test_required_rejects_untrusted_or_incompatible_tool(
    tmp_path: Path, tool_source: Path, problem: str
) -> None:
    """Missing and symlinked prepared binaries fail the suite."""
    jq = tool_source / "jq"
    if problem == "missing":
        jq.unlink()
    elif problem == "symlink":
        real = tool_source / "jq-real"
        jq.rename(real)
        jq.symlink_to(real.name)
    result = _run_setup(tmp_path, mode="required", source=tool_source)
    assert result.returncode != 0
    assert "jq" in result.stderr


@pytest.mark.parametrize("name", ["jq", "yq", "jsonschema", "oras"])
def test_required_exercises_every_tool_compatibility_probe(
    tmp_path: Path, tool_source: Path, name: str
) -> None:
    """Every member of an explicit prepared bundle has a failing probe test."""
    _fake_tool(tool_source, name, compatible=False)
    result = _run_setup(tmp_path, mode="required", source=tool_source)
    assert result.returncode != 0
    assert f"tool '{name}' is incompatible" in result.stderr


def test_jsonschema_probe_declares_its_dialect() -> None:
    """The real CLI rejects an otherwise valid schema with no default dialect."""
    source = SETUP_SUITE.read_text(encoding="utf-8")
    assert '"$schema":"https://json-schema.org/draft/2020-12/schema"' in source


@pytest.mark.parametrize("mode", ["", "unknown", "REQUIRED"])
def test_setup_rejects_empty_or_invalid_cache_mode(tmp_path: Path, mode: str) -> None:
    """Suite setup accepts only the exact required/disabled mode values."""
    result = _run_setup(tmp_path, mode=mode)
    assert result.returncode != 0
    assert "DEVFEATS_TEST_TOOL_CACHE" in result.stderr


@pytest.mark.parametrize("kind", ["relative", "symlink", "noncanonical"])
def test_required_rejects_unsafe_source_directory(
    tmp_path: Path, tool_source: Path, kind: str
) -> None:
    """Prepared source directories must be absolute, direct, and canonical."""
    if kind == "relative":
        source = Path("relative-tools")
    elif kind == "symlink":
        source = tmp_path / "source-link"
        source.symlink_to(tool_source, target_is_directory=True)
    else:
        source = tool_source / ".." / tool_source.name
    result = _run_setup(tmp_path, mode="required", source=source)
    assert result.returncode != 0
    assert "DEVFEATS_TEST_TOOL_SOURCE_DIR" in result.stderr


def test_disabled_does_not_probe_source_or_export_tools(tmp_path: Path) -> None:
    """Bare mode ignores even a hostile source path and clears inherited exports."""
    result = _run_setup(
        tmp_path,
        mode="disabled",
        source=tmp_path / "does not exist",
        after="""
for name in \
  DEVFEATS_TEST_TOOLS_DIR \
  DEVFEATS_TEST_JQ_BIN \
  DEVFEATS_TEST_YQ_BIN \
  DEVFEATS_TEST_JSONSCHEMA_BIN \
  DEVFEATS_TEST_ORAS_BIN
do
  [[ -z "${!name+x}" ]] || exit 91
done
""",
    )
    assert result.returncode == 0, result.stderr


def test_native_fallback_resolves_only_selection_required_tools(
    tmp_path: Path, tool_source: Path
) -> None:
    """Native lean setup needs jq/yq but not integration-only clients."""
    (tool_source / "jsonschema").unlink()
    (tool_source / "oras").unlink()
    result = _run_setup(
        tmp_path,
        mode="required",
        required="jq yq",
        path=f"{tool_source}:/usr/bin:/bin",
    )
    assert result.returncode == 0, result.stderr


def test_helper_fails_without_suite_export(tmp_path: Path) -> None:
    """Per-test wiring never silently skips or provisions a missing cache."""
    test_tmp = tmp_path / "test tmp"
    env = {**os.environ, "BATS_TEST_TMPDIR": str(test_tmp)}
    env.pop("DEVFEATS_TEST_JQ_BIN", None)
    result = subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"; test_tools__wire_jq',
            "_",
            str(HELPER),
        ],
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "suite-cached test tool jq is unavailable" in result.stderr


def test_helper_wiring_never_invokes_production_bootstrap_sentinels(
    tmp_path: Path,
) -> None:
    """Wiring consumes exports directly even when every bootstrap call would fail."""
    cached = tmp_path / "cached tools"
    cached.mkdir()
    tools: dict[str, Path] = {}
    for name in ("jq", "yq", "jsonschema", "oras"):
        path = cached / name
        path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        path.chmod(0o555)
        tools[name] = path
    test_tmp = tmp_path / "test tmp"
    marker = tmp_path / "bootstrap-called"
    env = {
        **os.environ,
        "BATS_TEST_TMPDIR": str(test_tmp),
        "DEVFEATS_TEST_JQ_BIN": str(tools["jq"]),
        "DEVFEATS_TEST_YQ_BIN": str(tools["yq"]),
        "DEVFEATS_TEST_JSONSCHEMA_BIN": str(tools["jsonschema"]),
        "DEVFEATS_TEST_ORAS_BIN": str(tools["oras"]),
        "SENTINEL_MARKER": str(marker),
    }
    result = subprocess.run(
        [
            "bash",
            "-c",
            """
for fn in bootstrap__jq bootstrap__yq bootstrap__jsonschema bootstrap__oras; do
  eval "$fn() { printf called > \"$SENTINEL_MARKER\"; return 99; }"
done
source "$1"
test_tools__wire_all
bootstrap__yq >/dev/null
[[ "$_BOOTSTRAP__YQ_BIN" == "$DEVFEATS_TEST_YQ_BIN" ]]
""",
            "_",
            str(HELPER),
        ],
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert not marker.exists()
    for name, source in tools.items():
        link = test_tmp / "bin" / name
        assert link.is_symlink()
        assert link.resolve() == source


def test_ordinary_tests_do_not_provision_real_tools() -> None:
    """Only dedicated bootstrap coverage may invoke real bootstrap provisioning."""
    obsolete = REPO_ROOT / "test/lib/helpers/bootstrap_tools.bash"
    assert not obsolete.exists()
    forbidden = (
        "test_bootstrap__",
        "helpers/bootstrap_tools",
        "/usr/local/bin/oras",
    )
    for path in (REPO_ROOT / "test/lib").rglob("*.bats"):
        if "bats" in path.relative_to(REPO_ROOT / "test/lib").parts:
            continue
        text = path.read_text(encoding="utf-8")
        assert not any(token in text for token in forbidden), path


def test_ordinary_setup_files_never_call_production_bootstrap() -> None:
    """Ordinary file-level setup cannot hide provisioning or false-green skips."""
    root = REPO_ROOT / "test/lib"
    for path in root.rglob("*.bats"):
        relative = path.relative_to(root)
        if "bats" in relative.parts or relative.parts[0] == "bootstrap":
            continue
        text = path.read_text(encoding="utf-8")
        setup_file = re.search(r"(?ms)^setup_file\(\)\s*\{(?P<body>.*?)^\}", text)
        if setup_file:
            assert "bootstrap__" not in setup_file.group("body"), path
        assert not re.search(
            r"\bskip\s+[^\n]*(jq|yq|jsonschema|oras|git|gpg|chsh)",
            text,
            flags=re.IGNORECASE,
        ), path
        assert not re.search(
            r"(?m)^\s*(install|cp|mv|ln)(?:\s+-\S+)*\s+[^\n]*/usr/local/bin(?:/|\s|$)",
            text,
        ), path


def test_real_tool_bootstrap_calls_have_a_narrow_unit_test_allowlist() -> None:
    """Prepared tests may fake bootstrap branches only in dedicated unit files."""
    root = REPO_ROOT / "test/lib"
    allowed = {"install_tools.bats", "json.bats", "ospkg.bats"}
    call = re.compile(
        r"(?m)^\s*(?:run(?:\s+--?\S+)*\s+)?bootstrap__(?:jq|yq|jsonschema|oras)\b"
    )
    observed: set[str] = set()
    for path in root.glob("*.bats"):
        if call.search(path.read_text(encoding="utf-8")):
            observed.add(path.name)
    assert observed <= allowed


def test_conditional_users_tests_wire_prepared_json_tools() -> None:
    """Context-backed users tests must not fall through to real bootstrapping."""
    source = (REPO_ROOT / "test/lib/users.bats").read_text(encoding="utf-8")
    test_names = (
        "users__first_writeable_path: uses platform-matching group over fallback",
        "users__first_writeable_path: skips non-matching group and uses fallback",
        "users__first_writeable_path: fails when no group's platform condition matches",
        "users__first_writeable_path: feat.version lte constraint "
        "selects matching group",
    )
    for test_name in test_names:
        match = re.search(
            rf'(?ms)^@test "{re.escape(test_name)}"\s*\{{(?P<body>.*?)^\}}',
            source,
        )
        assert match is not None, test_name
        body = match.group("body")
        assert "load 'helpers/test_tools'" in body, test_name
        assert "test_tools__wire_jq_yq" in body, test_name


def test_bootstrap_tests_pin_child_session_state_to_bats_tmpdir() -> None:
    """Bootstrap subprocesses leave scratch state inside BATS-owned cleanup scope."""
    source = (REPO_ROOT / "test/lib/bootstrap/bootstrap.bats").read_text(
        encoding="utf-8"
    )
    setup = re.search(r"(?ms)^setup\(\)\s*\{(?P<body>.*?)^\}", source)
    assert setup is not None
    body = setup.group("body")
    assert body.index("reload_lib") < body.index("_FILE__SESSION_ROOT=")
    assert '"${BATS_TEST_TMPDIR}/session"' in body
    assert "_FILE__SESSION_OWNED=false" in body
    assert "export _FILE__SESSION_ROOT _FILE__SESSION_OWNED" in body
