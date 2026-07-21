"""Regression tests for the shell library-test runner."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = REPO_ROOT / ".dev/scripts/test/run-unit.sh"
FORMATTER = REPO_ROOT / ".dev/scripts/test/format-unit-tap.bash"


def _run(
    repo: Path, *args: str, cwd: Path | None = None, **env: str
) -> subprocess.CompletedProcess[str]:
    run_env = {**os.environ, "REPO_ROOT": str(repo), **env}
    return subprocess.run(
        ["bash", str(RUNNER), *args],
        cwd=cwd or repo,
        env=run_env,
        check=False,
        capture_output=True,
        text=True,
    )


@pytest.fixture
def runner_repo(tmp_path: Path) -> Path:
    """Create a minimal repository tree with lean, integration, and vendor tests."""
    unit = tmp_path / "test/lib"
    integration = unit / "integration"
    bootstrap = unit / "bootstrap"
    vendor = unit / "bats/bats-core/bin"
    integration.mkdir(parents=True)
    bootstrap.mkdir(parents=True)
    vendor.mkdir(parents=True)
    for path in (unit / "alpha.bats", unit / "zeta.bats", integration / "alpha.bats"):
        path.write_text("#!/usr/bin/env bats\n", encoding="utf-8")
    (unit / "bats/vendor.bats").write_text("#!/usr/bin/env bats\n", encoding="utf-8")
    (bootstrap / "bootstrap.bats").write_text("#!/usr/bin/env bats\n", encoding="utf-8")
    fake_bats = vendor / "bats"
    fake_bats.write_text(
        '#!/usr/bin/env bash\nprintf \'%s\\n\' "$@" > "$BATS_ARGS_FILE"\n'
        'if [[ -n "${BATS_ENV_FILE:-}" ]]; then\n'
        "  printf '%s\\n%s\\n' \"$DEVFEATS_TEST_TOOL_CACHE\" "
        '"$DEVFEATS_TEST_REQUIRED_TOOLS" > "$BATS_ENV_FILE"\n'
        "fi\n"
        'if [[ -n "${BATS_TAP_FILE:-}" ]]; then\n'
        '  cat -- "$BATS_TAP_FILE"\n'
        "else\n"
        "  printf '1..0\\n'\n"
        "fi\n"
        'exit "${BATS_RC:-0}"\n',
        encoding="utf-8",
    )
    fake_bats.chmod(0o755)
    return tmp_path


def _lines(result: subprocess.CompletedProcess[str]) -> list[str]:
    assert result.returncode == 0, result.stderr
    return result.stdout.splitlines()


def _fake_command(directory: Path, name: str, body: str) -> Path:
    """Create one executable command override."""
    path = directory / name
    path.write_text(f"#!/usr/bin/env bash\n{body}\n", encoding="utf-8")
    path.chmod(0o755)
    return path


def _runner_path_without_locks(tmp_path: Path) -> str:
    """Build the runner's minimal command PATH without flock or shlock."""
    bin_dir = tmp_path / "runner-bin"
    bin_dir.mkdir()
    for command in ("bash", "dirname", "find", "mktemp", "rm", "sort"):
        target = shutil.which(command)
        assert target is not None
        (bin_dir / command).symlink_to(target)
    return str(bin_dir)


def _run_with_tap(
    repo: Path,
    tmp_path: Path,
    tap: str,
    *,
    bats_rc: int = 0,
) -> subprocess.CompletedProcess[str]:
    """Run the fake BATS executable with exact TAP and exit status."""
    tap_file = tmp_path / "fake-bats.tap"
    args_file = tmp_path / "fake-bats.args"
    tap_file.write_text(tap, encoding="utf-8")
    return _run(
        repo,
        BATS_ARGS_FILE=str(args_file),
        BATS_TAP_FILE=str(tap_file),
        BATS_RC=str(bats_rc),
    )


def test_real_repository_tier_counts_and_vendor_exclusion() -> None:
    """The ordinary suite has the audited 29/12/41 split and excludes bootstrap."""
    lean = _lines(_run(REPO_ROOT, "--list-files"))
    integration = _lines(_run(REPO_ROOT, "--tier", "integration", "--list-files"))
    all_tests = _lines(_run(REPO_ROOT, "--tier", "all", "--list-files"))
    assert len(lean) == 29
    assert len(integration) == 12
    assert len(all_tests) == 41
    assert all("/bootstrap/" not in path for path in all_tests)
    assert all_tests == sorted(set(lean + integration))
    assert not any(path.startswith("test/lib/bats/") for path in all_tests)


@pytest.mark.parametrize(
    ("args", "expected"),
    [
        (("--list-files",), ["test/lib/alpha.bats", "test/lib/zeta.bats"]),
        (
            ("--tier", "integration", "--list-files"),
            ["test/lib/integration/alpha.bats"],
        ),
        (
            ("--tier", "all", "--list-files"),
            [
                "test/lib/alpha.bats",
                "test/lib/integration/alpha.bats",
                "test/lib/zeta.bats",
            ],
        ),
        (("--module", "alpha", "--list-files"), ["test/lib/alpha.bats"]),
        (
            ("--tier", "all", "--module", "alpha", "--list-files"),
            ["test/lib/alpha.bats", "test/lib/integration/alpha.bats"],
        ),
        (
            ("--tier", "integration", "--module", "alpha", "--list-files"),
            ["test/lib/integration/alpha.bats"],
        ),
    ],
)
def test_tier_and_module_selection(
    runner_repo: Path,
    args: tuple[str, ...],
    expected: list[str],
) -> None:
    """Tier and module selectors produce the exact expected file set."""
    assert _lines(_run(runner_repo, *args)) == expected


@pytest.mark.parametrize("module", ["missing", "../alpha", "alpha.bats", "a/b", ".."])
def test_missing_or_unsafe_module_fails(runner_repo: Path, module: str) -> None:
    """Missing modules and unsafe basename syntax fail selection."""
    result = _run(runner_repo, "--module", module, "--list-files")
    assert result.returncode == 2


def test_exact_paths_are_canonical_sorted_and_deduplicated(runner_repo: Path) -> None:
    """Repeated exact paths are canonicalized, sorted, and deduplicated."""
    result = _run(
        runner_repo,
        "--path",
        "test/lib/zeta.bats",
        "--path",
        "test/lib/alpha.bats",
        "--path",
        "test/lib/zeta.bats",
        "--list-files",
    )
    assert _lines(result) == ["test/lib/alpha.bats", "test/lib/zeta.bats"]


def test_safe_metacharacter_paths_use_c_byte_order_and_exact_bats_argv(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """Safe unusual filenames retain exact argv values in deterministic C order."""
    unit = runner_repo / "test/lib"
    names = ["A mixed.bats", "a-[x]$?.bats", "É.bats", "é.bats"]
    for name in names:
        (unit / name).write_text("#!/usr/bin/env bats\n", encoding="utf-8")
    real_sort = shutil.which("sort")
    assert real_sort is not None
    fake_bin = tmp_path / "recording-sort"
    fake_bin.mkdir()
    sort_record = tmp_path / "sort-record"
    _fake_command(
        fake_bin,
        "sort",
        f'printf \'%s\\n\' "$LC_ALL" "$@" > "$SORT_RECORD"\nexec {real_sort} "$@"',
    )
    expected = sorted(
        [
            "test/lib/alpha.bats",
            "test/lib/zeta.bats",
            *(f"test/lib/{name}" for name in names),
        ],
        key=lambda value: value.encode(),
    )
    runner_env = {"SORT_RECORD": str(sort_record)}
    assert (
        _lines(
            _run(
                runner_repo,
                "--path-prepend",
                str(fake_bin),
                "--list-files",
                **runner_env,
            )
        )
        == expected
    )
    sort_call = sort_record.read_text(encoding="utf-8").splitlines()
    assert sort_call[0] == "C"
    assert sort_call[1] == "-zu"
    assert len(sort_call) == 3

    args_file = tmp_path / "unusual-bats-args"
    result = _run(
        runner_repo,
        "--path-prepend",
        str(fake_bin),
        BATS_ARGS_FILE=str(args_file),
        **runner_env,
    )
    assert result.returncode == 0
    argv = args_file.read_text(encoding="utf-8").splitlines()
    assert argv[-len(expected) :] == [str(runner_repo / path) for path in expected]


@pytest.mark.parametrize(
    "path",
    [
        "test/lib/missing.bats",
        "test/lib/alpha.txt",
        "test/lib",
        "test/lib/bats/vendor.bats",
        "test/lib/helpers/nested.bats",
        "outside.bats",
    ],
)
def test_invalid_explicit_paths_fail(runner_repo: Path, path: str) -> None:
    """Explicit paths reject missing, wrong-type, nested, and outside files."""
    (runner_repo / "test/lib/alpha.txt").write_text("x", encoding="utf-8")
    (runner_repo / "test/lib/helpers").mkdir(exist_ok=True)
    (runner_repo / "test/lib/helpers/nested.bats").write_text("x", encoding="utf-8")
    (runner_repo / "outside.bats").write_text("x", encoding="utf-8")
    result = _run(runner_repo, "--path", path, "--list-files")
    assert result.returncode == 2


def test_symlink_explicit_path_fails(runner_repo: Path) -> None:
    """Explicit symlink test files are rejected."""
    link = runner_repo / "test/lib/link.bats"
    link.symlink_to("alpha.bats")
    result = _run(runner_repo, "--path", str(link), "--list-files")
    assert result.returncode == 2
    assert "Symlink" in result.stderr


def test_symlink_parent_escape_fails(runner_repo: Path, tmp_path: Path) -> None:
    """Canonical parent validation rejects files reached through escaping symlinks."""
    outside = tmp_path / "outside-dir"
    outside.mkdir()
    (outside / "escaped.bats").write_text("x", encoding="utf-8")
    (runner_repo / "test/lib/escape").symlink_to(outside, target_is_directory=True)
    result = _run(
        runner_repo,
        "--path",
        "test/lib/escape/escaped.bats",
        "--list-files",
    )
    assert result.returncode == 2


@pytest.mark.parametrize(
    "args",
    [
        ("--path", "test/lib/alpha.bats", "--tier", "lean"),
        ("--path", "test/lib/alpha.bats", "--module", "alpha"),
    ],
)
def test_selector_conflicts_fail(runner_repo: Path, args: tuple[str, ...]) -> None:
    """Explicit paths cannot be combined with tier or module selection."""
    assert _run(runner_repo, *args, "--list-files").returncode == 2


def test_mixed_ordinary_and_bootstrap_exact_paths_fail(runner_repo: Path) -> None:
    """One BATS process cannot mix prepared and bare workload contracts."""
    result = _run(
        runner_repo,
        "--path",
        "test/lib/alpha.bats",
        "--path",
        "test/lib/bootstrap/bootstrap.bats",
        "--list-files",
    )
    assert result.returncode == 2
    assert "cannot be selected in the same run" in result.stderr


@pytest.mark.parametrize(
    ("path", "expected_tools"),
    [
        ("test/lib/alpha.bats", "jq yq"),
        ("test/lib/integration/json.bats", "jq yq jsonschema"),
        ("test/lib/integration/oci.bats", "jq yq oras"),
    ],
)
def test_ordinary_selection_derives_required_tools(
    runner_repo: Path, tmp_path: Path, path: str, expected_tools: str
) -> None:
    """Runner exports only native prerequisites needed by the selection."""
    selected = runner_repo / path
    selected.parent.mkdir(parents=True, exist_ok=True)
    selected.write_text("#!/usr/bin/env bats\n", encoding="utf-8")
    env_file = tmp_path / "bats-env"
    result = _run(
        runner_repo,
        "--path",
        path,
        BATS_ARGS_FILE=str(tmp_path / "bats-args"),
        BATS_ENV_FILE=str(env_file),
    )
    assert result.returncode == 0
    assert env_file.read_text(encoding="utf-8").splitlines() == [
        "required",
        expected_tools,
    ]


def test_bootstrap_selection_defaults_to_disabled_cache(
    runner_repo: Path, tmp_path: Path
) -> None:
    """Exact bootstrap selection receives no prepared tool requirements."""
    env_file = tmp_path / "bats-env"
    result = _run(
        runner_repo,
        "--path",
        "test/lib/bootstrap/bootstrap.bats",
        BATS_ARGS_FILE=str(tmp_path / "bats-args"),
        BATS_ENV_FILE=str(env_file),
    )
    assert result.returncode == 0
    assert env_file.read_text(encoding="utf-8").splitlines() == ["disabled", ""]


def test_incompatible_explicit_tool_cache_modes_fail(runner_repo: Path) -> None:
    """Callers cannot invert ordinary/prepared and bootstrap/bare contracts."""
    ordinary = _run(
        runner_repo,
        "--list-files",
        DEVFEATS_TEST_TOOL_CACHE="disabled",
    )
    bootstrap = _run(
        runner_repo,
        "--path",
        "test/lib/bootstrap/bootstrap.bats",
        "--list-files",
        DEVFEATS_TEST_TOOL_CACHE="required",
    )
    assert ordinary.returncode == 2
    assert bootstrap.returncode == 2


def test_bootstrap_rejects_prepared_source_dir(runner_repo: Path) -> None:
    """Bare bootstrap workload must not inherit the prepared source bundle."""
    result = _run(
        runner_repo,
        "--path",
        "test/lib/bootstrap/bootstrap.bats",
        "--list-files",
        DEVFEATS_TEST_TOOL_SOURCE_DIR="/opt/prepared",
    )
    assert result.returncode == 2


def test_bootstrap_rejects_parallel_jobs(runner_repo: Path) -> None:
    """Mutating bootstrap tests cannot share one container concurrently."""
    result = _run(
        runner_repo,
        "--path",
        "test/lib/bootstrap/bootstrap.bats",
        "--jobs",
        "2",
        "--list-files",
    )
    assert result.returncode == 2
    assert "must run serially" in result.stderr


@pytest.mark.parametrize(
    "value",
    [
        "0",
        "-1",
        "abc",
        "1+1",
        "x[$(id)]",
        "257",
        pytest.param("9223372036854775808", id="signed-overflow"),
        pytest.param("18446744073709551616", id="unsigned-overflow"),
        pytest.param("9" * 10000, id="very-long-decimal"),
    ],
)
def test_invalid_jobs_fail(runner_repo: Path, value: str) -> None:
    """Job counts reject syntax, bounds, overflow inputs, and huge decimals."""
    assert _run(runner_repo, "--jobs", value, "--list-files").returncode == 2


@pytest.mark.parametrize("value", ["1", "256"])
def test_jobs_bounds_are_accepted(runner_repo: Path, value: str) -> None:
    """Both documented job-count boundaries pass validation."""
    assert _run(runner_repo, "--jobs", value, "--list-files").returncode == 0


@pytest.mark.parametrize(
    "option",
    ["--tier", "--module", "--path", "--filter", "--jobs", "--path-prepend"],
)
def test_missing_option_values_fail(runner_repo: Path, option: str) -> None:
    """Every value-taking option reports a missing value as usage error."""
    assert _run(runner_repo, option).returncode == 2


def test_jobs_filter_forwarding_and_bats_exit_preservation(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """Jobs and filters reach BATS exactly and its status is preserved."""
    args_file = tmp_path / "bats-args"
    result = _run(
        runner_repo,
        "--jobs",
        "3",
        "--filter",
        "alpha test",
        BATS_ARGS_FILE=str(args_file),
        BATS_RC="7",
    )
    assert result.returncode == 7
    args = args_file.read_text(encoding="utf-8").splitlines()
    assert args[:10] == [
        "--print-output-on-failure",
        "--formatter",
        str(runner_repo / ".dev/scripts/test/format-unit-tap.bash"),
        "--setup-suite-file",
        str(runner_repo / "test/lib/setup_suite.bash"),
        "--jobs",
        "3",
        "--no-parallelize-across-files",
        "--filter",
        "alpha test",
    ]
    assert args[-2:] == [
        str(runner_repo / "test/lib/alpha.bats"),
        str(runner_repo / "test/lib/zeta.bats"),
    ]


def test_max_jobs_and_dash_prefixed_filter_are_forwarded(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """The maximum jobs value and --filter= form reach BATS exactly."""
    args_file = tmp_path / "max-jobs-args"
    result = _run(
        runner_repo,
        "--jobs",
        "256",
        "--filter=--dash-prefixed",
        BATS_ARGS_FILE=str(args_file),
    )
    assert result.returncode == 0
    argv = args_file.read_text(encoding="utf-8").splitlines()
    jobs_index = argv.index("--jobs")
    filter_index = argv.index("--filter")
    assert argv[jobs_index + 1] == "256"
    assert argv[jobs_index : jobs_index + 3] == [
        "--jobs",
        "256",
        "--no-parallelize-across-files",
    ]
    assert argv[filter_index + 1] == "--dash-prefixed"


@pytest.mark.parametrize("args", [(), ("--jobs", "1")], ids=["default", "explicit"])
def test_serial_run_does_not_forward_parallel_flags(
    runner_repo: Path, tmp_path: Path, args: tuple[str, ...]
) -> None:
    """Default and explicit serial execution omit both BATS parallel flags."""
    args_file = tmp_path / "bats-args"
    result = _run(runner_repo, *args, BATS_ARGS_FILE=str(args_file))
    assert result.returncode == 0
    argv = args_file.read_text(encoding="utf-8").splitlines()
    assert "--jobs" not in argv
    assert "--no-parallelize-across-files" not in argv


def test_parallel_run_fails_before_bats_without_a_lock_provider(
    runner_repo: Path, tmp_path: Path
) -> None:
    """Within-file concurrency requires a BATS semaphore implementation."""
    args_file = tmp_path / "bats-args"
    result = _run(
        runner_repo,
        "--jobs",
        "2",
        PATH=_runner_path_without_locks(tmp_path),
        BATS_ARGS_FILE=str(args_file),
    )
    assert result.returncode == 1
    assert "parallel tests require flock or shlock on PATH" in result.stderr
    assert not args_file.exists()


def test_list_files_does_not_require_a_lock_provider(
    runner_repo: Path, tmp_path: Path
) -> None:
    """Selection-only parallel invocations do not need runtime infrastructure."""
    result = _run(
        runner_repo,
        "--jobs",
        "2",
        "--list-files",
        PATH=_runner_path_without_locks(tmp_path),
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["test/lib/alpha.bats", "test/lib/zeta.bats"]


def test_parallelization_opt_outs_and_fixture_isolation_are_allowlisted() -> None:
    """Only audited integration hazards disable within-file parallelization."""
    unit_dir = REPO_ROOT / "test/lib"
    first_party = [
        *unit_dir.glob("*.bats"),
        *(unit_dir / "integration").glob("*.bats"),
        *(unit_dir / "bootstrap").glob("*.bats"),
    ]
    opt_out_assignment = re.compile(
        r"^[ \t]*(?:export[ \t]+)?BATS_NO_PARALLELIZE_WITHIN_FILE[ \t]*=",
        re.MULTILINE,
    )
    opt_outs = {
        path.relative_to(REPO_ROOT).as_posix()
        for path in first_party
        if opt_out_assignment.search(path.read_text(encoding="utf-8"))
    }
    assert opt_outs == {
        "test/lib/integration/npm.bats",
        "test/lib/integration/ospkg.bats",
        "test/lib/integration/users.bats",
    }

    runner = RUNNER.read_text(encoding="utf-8")
    assert "Bootstrap tests must run serially; --jobs must be 1." in runner

    net = (unit_dir / "net.bats").read_text(encoding="utf-8")
    assert "_created_ca_bundle" not in net
    assert 'mkdir -p "$(dirname "$_ca_bundle")"' not in net
    assert 'rm -f "$_ca_bundle"' not in net
    assert '> "$_ca_bundle"' not in net

    for relative in ("argparse.bats", "os.bats", "oci.bats"):
        source = (unit_dir / relative).read_text(encoding="utf-8")
        for line in source.splitlines():
            if "mktemp" in line and not line.lstrip().startswith("#"):
                assert "BATS_TEST_TMPDIR" in line


def test_tap_summary_counts_only_completed_top_level_results(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """A complete plan counts result lines but ignores nested TAP-like diagnostics."""
    result = _run_with_tap(
        runner_repo,
        tmp_path,
        """TAP version 13
1..2
ok 1 first test
  not ok 98 nested diagnostic
    ok 99 more nested output
ok 2 second test
""",
    )
    assert result.returncode == 0
    assert (
        "── Summary: 2/2 completed, 2 passed, 0 failed, 0 skipped, "
        "0 TODO, 0 incomplete ──"
    ) in result.stdout


def test_tap_summary_reports_explicit_failure_name(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """A top-level not-ok result is counted and listed without its directive."""
    result = _run_with_tap(
        runner_repo,
        tmp_path,
        """1..2
ok 1 working test
not ok 2 broken feature # failure detail
# failure diagnostics
""",
        bats_rc=1,
    )
    assert result.returncode == 1
    assert (
        "── Summary: 2/2 completed, 1 passed, 1 failed, 0 skipped, "
        "0 TODO, 0 incomplete ──"
    ) in result.stdout
    assert "Failing tests:\n  - broken feature # failure detail\n" in result.stdout
    assert result.stderr == ""


@pytest.mark.parametrize("bats_rc", [7, 130])
def test_tap_summary_never_calls_missing_results_passed(
    runner_repo: Path,
    tmp_path: Path,
    bats_rc: int,
) -> None:
    """Truncated TAP reports missing results as incomplete and preserves BATS status."""
    result = _run_with_tap(
        runner_repo,
        tmp_path,
        """1..4
ok 1 completed test
not ok 2 failed before interruption
    ok 3 nested diagnostic, not a result
Bail out! interrupted
""",
        bats_rc=bats_rc,
    )
    assert result.returncode == bats_rc
    assert (
        "── Summary: 2/4 completed, 1 passed, 1 failed, 0 skipped, "
        "0 TODO, 2 incomplete ──"
    ) in result.stdout
    assert "3/4 passed" not in result.stdout
    assert "Failing tests:\n  - failed before interruption\n" in result.stdout


def test_tap_summary_reports_skip_directives_separately(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """Case-insensitive TAP skip directives are neither passed nor failed."""
    result = _run_with_tap(
        runner_repo,
        tmp_path,
        """1..3
ok 1 ordinary result
ok 2 unavailable here # skip optional dependency
not ok 3 unsupported here # SKIP platform exclusion
""",
    )
    assert result.returncode == 0
    assert (
        "── Summary: 3/3 completed, 1 passed, 0 failed, 2 skipped, "
        "0 TODO, 0 incomplete ──"
    ) in result.stdout
    assert "Failing tests:" not in result.stdout


def test_tap_summary_handles_zero_test_plan(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """A valid zero-test plan has no inferred results or missing tests."""
    result = _run_with_tap(runner_repo, tmp_path, "1..0\n")
    assert result.returncode == 0
    assert (
        "── Summary: 0/0 completed, 0 passed, 0 failed, 0 skipped, "
        "0 TODO, 0 incomplete ──"
    ) in result.stdout


@pytest.mark.parametrize(
    ("tap", "summary", "error"),
    [
        pytest.param(
            "1..2\nok 1 only result\n",
            "1/2 completed, 1 passed, 0 failed, 0 skipped, 0 TODO, 1 incomplete",
            "missing 1 planned result",
            id="incomplete",
        ),
        pytest.param(
            "ok 1 result without plan\n",
            "1 completed (planned total unavailable), 1 passed",
            "TAP plan is missing",
            id="no-plan",
        ),
        pytest.param(
            "1..1\nBail out! setup crashed\nok 1 ignored after bailout\n",
            "0/1 completed, 0 passed, 0 failed, 0 skipped, 0 TODO, 1 incomplete",
            "Bail out! was reported",
            id="bailout-and-post-bailout-result",
        ),
        pytest.param(
            "1..1\nok not-a-number malformed result\n",
            "0/1 completed, 0 passed, 0 failed, 0 skipped, 0 TODO, 1 incomplete",
            "unrecognized top-level TAP",
            id="malformed-result",
        ),
    ],
)
def test_invalid_tap_from_successful_bats_forces_infrastructure_failure(
    runner_repo: Path,
    tmp_path: Path,
    tap: str,
    summary: str,
    error: str,
) -> None:
    """BATS cannot return success when its TAP is incomplete or invalid."""
    result = _run_with_tap(runner_repo, tmp_path, tap)
    assert result.returncode == 1
    assert summary in result.stdout
    assert "Test runner infrastructure failure: invalid TAP output" in result.stderr
    assert error in result.stderr


@pytest.mark.parametrize(
    ("bats_rc", "expected_stderr"),
    [
        pytest.param(1, "", id="matching-failure-status"),
        pytest.param(
            0,
            "BATS exited with status 0 but TAP reported 1 failed test(s).",
            id="contradictory-success-status",
        ),
    ],
)
def test_not_ok_is_a_test_outcome_not_protocol_corruption(
    runner_repo: Path,
    tmp_path: Path,
    bats_rc: int,
    expected_stderr: str,
) -> None:
    """Valid failing TAP is ordinary failure unless the producer exits zero."""
    result = _run_with_tap(
        runner_repo,
        tmp_path,
        "1..1\nnot ok 1 explicit failure\n",
        bats_rc=bats_rc,
    )
    assert result.returncode == 1
    assert (
        "1/1 completed, 0 passed, 1 failed, 0 skipped, 0 TODO, 0 incomplete"
    ) in result.stdout
    assert "Failing tests:\n  - explicit failure\n" in result.stdout
    assert "invalid TAP output" not in result.stderr
    if expected_stderr:
        assert result.stderr == (
            f"⛔ Test runner infrastructure failure: {expected_stderr}\n"
        )
    else:
        assert result.stderr == ""


@pytest.mark.parametrize(
    "plan",
    [
        pytest.param("1..0", id="plain"),
        pytest.param("1..0 # SKIP no matching tests", id="skip"),
        pytest.param("1..0 # sKiP", id="mixed-case-skip"),
        pytest.param("1..0 # Skipped: filter selected no tests", id="skipped"),
        pytest.param("1..0 # sKiPpEd: none", id="mixed-case-skipped"),
    ],
)
def test_zero_plan_accepts_standard_skip_all_forms(
    runner_repo: Path,
    tmp_path: Path,
    plan: str,
) -> None:
    """A zero plan accepts no suffix or a recognized skip-all directive."""
    result = _run_with_tap(runner_repo, tmp_path, f"{plan}\n")
    assert result.returncode == 0
    assert "0/0 completed" in result.stdout
    assert result.stderr == ""


@pytest.mark.parametrize(
    ("plan", "error"),
    [
        pytest.param(
            "1..0 # TODO later",
            "unsupported directive",
            id="todo",
        ),
        pytest.param(
            "1..0 # arbitrary comment",
            "unsupported directive",
            id="unknown",
        ),
        pytest.param(
            "1..0 # Skipped without-colon",
            "unsupported directive",
            id="malformed-skipped",
        ),
        pytest.param(
            "1..1 # SKIP incorrectly suppresses a planned test",
            "skip-all directive requires a zero-test plan",
            id="nonzero-skip",
        ),
    ],
)
def test_plan_rejects_unsupported_or_nonzero_skip_directives(
    runner_repo: Path,
    tmp_path: Path,
    plan: str,
    error: str,
) -> None:
    """Plan suffixes are limited to skip-all syntax on an empty plan."""
    result = _run_with_tap(runner_repo, tmp_path, f"{plan}\n")
    assert result.returncode == 1
    assert error in result.stderr
    assert "invalid TAP output" in result.stderr


def test_real_bats_zero_filter_output_is_accepted() -> None:
    """The vendored BATS formatter's real zero-selection TAP remains valid."""
    result = _run(
        REPO_ROOT,
        "--module",
        "posix",
        "--filter",
        "^__devfeats_no_such_test__$",
    )
    assert result.returncode == 0
    assert "1..0" in result.stdout
    assert "0/0 completed" in result.stdout
    assert result.stderr == ""


def test_plan_after_all_results_is_valid(runner_repo: Path, tmp_path: Path) -> None:
    """TAP permits its single plan after all result lines."""
    result = _run_with_tap(
        runner_repo,
        tmp_path,
        "ok 1 first\nok 2 second\n1..2\n",
    )
    assert result.returncode == 0
    assert (
        "2/2 completed, 2 passed, 0 failed, 0 skipped, 0 TODO, 0 incomplete"
    ) in result.stdout
    assert result.stderr == ""


@pytest.mark.parametrize(
    ("tap", "error"),
    [
        pytest.param(
            "1..1\n1..1\nok 1 result\n",
            "duplicate plans",
            id="duplicate-plan",
        ),
        pytest.param(
            "1..1\n1..2\nok 1 result\n",
            "conflicting plans",
            id="conflicting-plans",
        ),
        pytest.param(
            "ok 1 first\n1..2\nok 2 second\n",
            "plan appears between result lines",
            id="middle-plan",
        ),
    ],
)
def test_duplicate_conflicting_and_middle_plans_are_invalid(
    runner_repo: Path,
    tmp_path: Path,
    tap: str,
    error: str,
) -> None:
    """Exactly one plan is allowed, either before or after all results."""
    result = _run_with_tap(runner_repo, tmp_path, tap)
    assert result.returncode == 1
    assert error in result.stderr


@pytest.mark.parametrize(
    ("tap", "error", "summary"),
    [
        pytest.param(
            "1..2\nok 01 first\nok 1 duplicate normalized ID\n",
            "result number 1 is duplicated",
            "1/2 completed",
            id="normalized-duplicate-id",
        ),
        pytest.param(
            "1..1\nok 2 outside\n",
            "result number 2 is outside plan 1..1",
            "0/1 completed",
            id="out-of-range-id",
        ),
        pytest.param(
            "1..2\nok 2 leaves-id-one-missing\n",
            "missing 1 planned result",
            "1/2 completed",
            id="missing-id",
        ),
        pytest.param(
            "1..1\nok 999999999999999999999 oversized\n",
            "unsupported test number",
            "0/1 completed",
            id="oversized-id",
        ),
        pytest.param(
            "1..999999999999999999999\n",
            "unsupported numeric total",
            "planned total unavailable",
            id="oversized-plan",
        ),
        pytest.param(
            "1..0\nok 1 impossible\n",
            "outside plan 1..0",
            "0/0 completed",
            id="result-with-zero-plan",
        ),
    ],
)
def test_tap_result_id_and_plan_invariants_are_enforced(
    runner_repo: Path,
    tmp_path: Path,
    tap: str,
    error: str,
    summary: str,
) -> None:
    """Normalized IDs must uniquely and completely cover the bounded plan."""
    result = _run_with_tap(runner_repo, tmp_path, tap)
    assert result.returncode == 1
    assert error in result.stderr
    assert summary in result.stdout


def test_tap_skip_and_todo_directives_are_structural_and_separate(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """Terminal SKIP/TODO directives are case-insensitive non-failure results."""
    result = _run_with_tap(
        runner_repo,
        tmp_path,
        """TAP version 13
1..3
ok 1 ordinary
ok 2 absent dependency # sKiP optional
not ok 3 future behavior # ToDo expected for now
""",
    )
    assert result.returncode == 0
    assert (
        "3/3 completed, 1 passed, 0 failed, 1 skipped, 1 TODO, 0 incomplete"
    ) in result.stdout
    assert "Failing tests:" not in result.stdout


def test_bats_formatter_disambiguates_directive_tokens_in_names_and_reasons() -> None:
    """Separate begin events make raw names and skip reasons unambiguous."""
    extended_tap = """1..4
begin 1 pass # TODO in name
ok 1 pass # TODO in name
begin 2 skipped case
ok 2 skipped case # skip revisit # TODO later
begin 3 pass # skip in name
ok 3 pass # skip in name
begin 4 failed # TODO in name
not ok 4 failed # TODO in name
"""
    result = subprocess.run(
        [str(FORMATTER)],
        input=extended_tap,
        env={
            **os.environ,
            "BATS_ROOT": str(REPO_ROOT / "test/lib/bats/bats-core"),
            "BATS_LIBDIR": "lib",
        },
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert (
        result.stdout
        == """1..4
# devfeats-test-name 1 pass # TODO in name
ok 1
# devfeats-test-name 2 skipped case
ok 2 # SKIP
# devfeats-test-name 3 pass # skip in name
ok 3
# devfeats-test-name 4 failed # TODO in name
not ok 4
"""
    )


def test_canonical_formatter_names_do_not_change_result_classification(
    runner_repo: Path, tmp_path: Path
) -> None:
    """Machine-generated name comments cannot masquerade as directives."""
    result = _run_with_tap(
        runner_repo,
        tmp_path,
        """1..3
# devfeats-test-name 1 pass # TODO in name
ok 1
# devfeats-test-name 2 skipped
ok 2 # SKIP
# devfeats-test-name 3 failed # TODO in name
not ok 3
""",
        bats_rc=1,
    )
    assert result.returncode == 1
    assert "1 passed, 1 failed, 1 skipped, 0 TODO" in result.stdout
    assert "Failing tests:\n  - failed # TODO in name\n" in result.stdout


def test_zero_plan_uses_bash_4_nounset_safe_empty_array_expansion() -> None:
    """Empty result arrays use the Bash 4.0-safe conditional expansion idiom."""
    source = RUNNER.read_text(encoding="utf-8")
    assert '${_tap_result_ids[@]+"${_tap_result_ids[@]}"}' in source


def test_conflicting_tap_directives_are_invalid(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """One result cannot carry both SKIP and TODO semantics."""
    result = _run_with_tap(
        runner_repo,
        tmp_path,
        "1..1\nnot ok 1 ambiguous # SKIP first # TODO second\n",
    )
    assert result.returncode == 1
    assert "conflicting SKIP and TODO directives" in result.stderr


@pytest.mark.parametrize(
    ("bats_rc", "tee_rc", "expected"),
    [
        pytest.param(130, 23, 130, id="bats-before-tee-and-tap"),
        pytest.param(0, 23, 23, id="tee-before-tap"),
        pytest.param(0, 0, 1, id="invalid-tap-last"),
    ],
)
def test_bats_tee_and_tap_validation_exit_precedence(
    runner_repo: Path,
    tmp_path: Path,
    bats_rc: int,
    tee_rc: int,
    expected: int,
) -> None:
    """BATS status wins, then tee status, then invalid-TAP infrastructure status."""
    real_tee = shutil.which("tee")
    assert real_tee is not None
    fake_bin = tmp_path / f"fake-tee-{bats_rc}-{tee_rc}"
    fake_bin.mkdir()
    _fake_command(fake_bin, "tee", f'{real_tee!s} "$@"\nexit {tee_rc}')
    tap_file = tmp_path / "missing-plan.tap"
    tap_file.write_text("ok 1 no plan\n", encoding="utf-8")
    result = _run(
        runner_repo,
        "--path-prepend",
        str(fake_bin),
        BATS_ARGS_FILE=str(tmp_path / "precedence.args"),
        BATS_TAP_FILE=str(tap_file),
        BATS_RC=str(bats_rc),
    )
    assert result.returncode == expected
    assert "TAP plan is missing" in result.stderr


@pytest.mark.parametrize("command", ["find", "sort"])
def test_selection_command_failure_is_infrastructure_error_without_bats(
    runner_repo: Path,
    tmp_path: Path,
    command: str,
) -> None:
    """A failed selection producer exits one and never invokes BATS."""
    fake_bin = tmp_path / f"fake-{command}"
    fake_bin.mkdir()
    _fake_command(fake_bin, command, "exit 37")
    args_file = tmp_path / f"{command}-bats-args"
    result = _run(
        runner_repo,
        "--path-prepend",
        str(fake_bin),
        BATS_ARGS_FILE=str(args_file),
    )
    assert result.returncode == 1
    assert "infrastructure failure" in result.stderr
    assert not args_file.exists()


def test_tee_failure_is_reported_when_bats_succeeds(
    runner_repo: Path,
    tmp_path: Path,
) -> None:
    """A failed tee controls status only after a successful BATS run."""
    real_tee = shutil.which("tee")
    assert real_tee is not None
    fake_bin = tmp_path / "fake-tee"
    fake_bin.mkdir()
    _fake_command(fake_bin, "tee", f'{real_tee!s} "$@"\nexit 23')
    args_file = tmp_path / "tee-bats-args"
    result = _run(
        runner_repo,
        "--path-prepend",
        str(fake_bin),
        BATS_ARGS_FILE=str(args_file),
    )
    assert result.returncode == 23
    assert "tee exited with status 23" in result.stderr
    assert args_file.exists()


def test_invalid_tier_unknown_option_and_help(runner_repo: Path) -> None:
    """Tier/option usage errors and help use their documented statuses."""
    assert _run(runner_repo, "--tier", "everything", "--list-files").returncode == 2
    assert _run(runner_repo, "--unknown").returncode == 2
    help_result = _run(runner_repo, "--help")
    assert help_result.returncode == 0
    assert "1..256" in help_result.stdout
    assert "--filter=<regex>" in help_result.stdout
