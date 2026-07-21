"""Behavioral tests for the prepared library-test tool installer."""

# Test names state their contracts; repeating each as a one-line docstring adds noise.
# ruff: noqa: D103

from __future__ import annotations

import os
import signal
import stat
import subprocess
import time
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
INSTALLER = REPO_ROOT / "test/envs/install-lib-test-tools.sh"
TOOLS = ("jq", "yq", "jsonschema", "oras")


def _run_installer(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/bin/sh", str(INSTALLER)],
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def _script(path: Path, content: str) -> None:
    path.write_text(f"#!/bin/sh\n{content}", encoding="utf-8")
    path.chmod(0o755)


def _tool_script(name: str) -> str:
    versions = {
        "jq": "jq-1.8.2",
        "yq": "yq (https://github.com/mikefarah/yq/) version v4.53.2",
        "jsonschema": "16.2.0",
    }
    if name == "oras":
        behavior = 'if [ "$1" = version ]; then printf "Version:        1.3.2\\n"; fi\n'
    elif name == "jsonschema":
        behavior = 'if [ "$1" = version ]; then printf "16.2.0\\n"; fi\n'
    else:
        version = versions[name]
        behavior = (
            f'if [ "$1" = --version ]; then printf "%s\\n" \'{version}\'; '
            'else printf "42\\n"; fi\n'
        )
    return f'#!/bin/sh\nprintf "probe:{name}:%s\\n" "$*" >> "$TRACE"\n{behavior}'


def _harness(
    tmp_path: Path,
    pm: str | None = "apk",
    *,
    kernel: str = "Linux",
    machine: str = "x86_64",
    musl: bool = False,
    lock_provider: str | None = "flock",
) -> dict[str, str]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    trace = tmp_path / "trace"
    tool_dir = tmp_path / "tools"
    work_dir = tmp_path / "work"
    for command, target in (
        ("cat", "/bin/cat"),
        ("mkdir", "/bin/mkdir"),
        ("grep", "/usr/bin/grep"),
    ):
        (bin_dir / command).symlink_to(target)
    for command in (
        "git",
        "gpg",
        "cmp",
        "find",
        "install",
        "gzip",
        "xz",
        "bzip2",
        "getent",
        "groupadd",
        "useradd",
        "userdel",
        "groupdel",
        "chsh",
    ):
        (bin_dir / command).symlink_to("/bin/true")
    # Alpine's package-manager mock must provision flock from the requested
    # package; seeding it here would let a missing APK dependency pass.
    if lock_provider is not None and not (pm == "apk" and lock_provider == "flock"):
        assert lock_provider in {"flock", "shlock"}
        (bin_dir / lock_provider).symlink_to("/bin/true")
    for command in ("cp", "chmod"):
        _script(
            bin_dir / command,
            f'printf "{command}:%s\\n" "$*" >> "$TRACE"\nexec /bin/{command} "$@"\n',
        )
    _script(
        bin_dir / "rm",
        'printf "rm:%s\\n" "$*" >> "$TRACE"\n'
        'case "$*" in *"$SAFE_WORK_DIR"*|*"$SAFE_TOOL_DIR"*) '
        'exec /bin/rm "$@" ;; esac\n'
        "exit 0\n",
    )
    _script(bin_dir / "sleep", ":\n")
    _script(
        bin_dir / "uname",
        f'case "$1" in -s) printf "%s\\n" "{kernel}" ;; '
        f'-m) printf "%s\\n" "{machine}" ;; *) exit 2 ;; esac\n',
    )
    _script(
        bin_dir / "ldd",
        f'printf "%s\\n" "{"musl libc" if musl else "glibc"}"\n',
    )
    _script(
        bin_dir / "mktemp",
        f"mkdir -p '{work_dir}'\nprintf '%s\\n' '{work_dir}'\n",
    )
    if pm is not None:
        _script(
            bin_dir / pm,
            'printf "pm:%s\\n" "$*" >> "$TRACE"\n'
            'case "$*" in *install*|*add*|*-Syu*)\n'
            '  count=$(cat "$PM_ATTEMPT_FILE" 2>/dev/null || printf 0)\n'
            "  count=$((count + 1))\n"
            '  printf "%s" "$count" > "$PM_ATTEMPT_FILE"\n'
            '  [ "$count" -le "${PM_FAILS:-0}" ] && exit "${PM_FAIL_RC:-1}"\n'
            '  case " $* " in *" flock "*)\n'
            '    if [ "${PM_PROVISION_LOCK:-1}" = 1 ]; then\n'
            "      printf '#!/bin/sh\\nexit 0\\n' > \"$MOCK_BIN/flock\"\n"
            '      chmod +x "$MOCK_BIN/flock"\n'
            "    fi\n"
            "  ;; esac\n"
            '  exit "${PM_RC:-0}"\n'
            ";; esac\n"
            "exit 0\n",
        )
    if kernel == "Darwin":
        _script(
            bin_dir / "brew",
            'printf "brew:%s\\n" "$*" >> "$TRACE"\nexit "${BREW_RC:-0}"\n',
        )
    _script(
        bin_dir / "curl",
        "url= out= argv=$*\n"
        'while [ "$#" -gt 0 ]; do\n'
        '  case "$1" in -o) out=$2; shift 2 ;; '
        "http*) url=$1; shift ;; *) shift ;; esac\n"
        "done\n"
        'printf "curl:%s\\n" "$argv" >> "$TRACE"\n'
        'case "$url" in *"${CURL_FAIL_MATCH:-__never__}"*) '
        'exit "${CURL_RC:-22}" ;; esac\n'
        'case "$url" in *jqlang*) tool=jq ;; *mikefarah*) tool=yq ;; '
        '*) printf archive > "$out"; exit 0 ;; esac\n'
        'case "$tool" in jq) version="jq-1.8.2" ;; '
        '*) version="yq (https://github.com/mikefarah/yq/) version v4.53.2" ;; esac\n'
        "{\n"
        "  printf '#!/bin/sh\\n'\n"
        '  printf \'printf "probe:%s:%%s\\\\n" "$*" >> "$TRACE"\\n\' "$tool"\n'
        '  printf \'if [ "$1" = --version ]; then printf "%%s\\\\n" "%s"; '
        'else printf "42\\\\n"; fi\\n\' "$version"\n'
        '} > "$out"\n'
        'chmod +x "$out"\n',
    )
    _script(
        bin_dir / "unzip",
        'printf "unzip:%s\\n" "$*" >> "$TRACE"\n'
        'dest= member=\nwhile [ "$#" -gt 0 ]; do '
        'case "$1" in -d) dest=$2; shift 2 ;; -*) shift ;; '
        "*) member=$1; shift ;; esac; done\n"
        'mkdir -p "$dest/${member%/*}"\n'
        'printf \'%s\' "$JSONSCHEMA_SCRIPT" > "$dest/$member"\n',
    )
    _script(
        bin_dir / "tar",
        'printf "tar:%s\\n" "$*" >> "$TRACE"\n'
        'dest=\nwhile [ "$#" -gt 0 ]; do '
        'case "$1" in -C) dest=$2; shift 2 ;; *) shift ;; esac; done\n'
        'printf \'%s\' "$ORAS_SCRIPT" > "$dest/oras"\n',
    )
    checksum_name = "shasum" if kernel == "Darwin" else "sha256sum"
    manifest_arg = "manifest=$4" if checksum_name == "shasum" else "manifest=$2"
    _script(
        bin_dir / checksum_name,
        f'printf "{checksum_name}:%s\\n" "$*" >> "$TRACE"\n'
        f"{manifest_arg}\n"
        'cat "$manifest" >> "$TRACE"\n'
        'exit "${SHA_RC:-0}"\n',
    )
    _script(
        bin_dir / "chown",
        'printf "chown:%s\\n" "$*" >> "$TRACE"\nexit "${CHOWN_RC:-0}"\n',
    )
    return {
        "PATH": str(bin_dir),
        "TRACE": str(trace),
        "PM_RC": "0",
        "PM_FAILS": "0",
        "PM_FAIL_RC": "1",
        "PM_PROVISION_LOCK": "1",
        "PM_ATTEMPT_FILE": str(tmp_path / "pm-attempts"),
        "MOCK_BIN": str(bin_dir),
        "CURL_FAIL_MATCH": "__never__",
        "CURL_RC": "22",
        "CHOWN_RC": "0",
        "BREW_RC": "0",
        "SAFE_WORK_DIR": str(work_dir),
        "SAFE_TOOL_DIR": str(tool_dir),
        "DEVFEATS_LIB_TEST_TOOL_DIR": str(tool_dir),
        "JSONSCHEMA_SCRIPT": _tool_script("jsonschema"),
        "ORAS_SCRIPT": _tool_script("oras"),
    }


LINUX_PACKAGES = {
    "apt-get": [
        "update -qq",
        "install -y --no-install-recommends ca-certificates curl coreutils "
        "diffutils git gnupg passwd findutils util-linux tar gzip unzip xz-utils "
        "bzip2",
        "clean",
    ],
    "apk": [
        "add --no-cache ca-certificates curl coreutils diffutils git gnupg "
        "shadow findutils flock tar gzip unzip xz bzip2"
    ],
    "dnf": [
        "install -y ca-certificates curl diffutils git gnupg2 shadow-utils "
        "util-linux-core util-linux-user findutils tar gzip unzip xz bzip2",
        "clean all",
    ],
    "zypper": [
        "--non-interactive install --no-recommends ca-certificates curl "
        "coreutils diffutils git gpg2 shadow util-linux findutils tar gzip "
        "unzip xz bzip2",
        "clean --all",
    ],
    "pacman": [
        "-Syu --noconfirm --needed ca-certificates curl coreutils diffutils "
        "git gnupg shadow util-linux findutils tar gzip unzip xz bzip2",
        "-Scc --noconfirm",
    ],
}


@pytest.mark.parametrize("pm", LINUX_PACKAGES)
def test_linux_installer_provisions_prerequisites_and_four_tools(
    tmp_path: Path, pm: str
) -> None:
    env = _harness(tmp_path, pm)
    result = _run_installer(env)
    assert result.returncode == 0, result.stderr
    trace = Path(env["TRACE"]).read_text(encoding="utf-8")
    assert trace.count("curl:") == 4
    assert trace.count("sha256sum:-c") == 4
    assert trace.index("sha256sum:-c") < trace.index("unzip:")
    assert trace.index("sha256sum:-c") < trace.index("tar:")
    assert trace.index("unzip:") < trace.index("probe:jsonschema:")
    assert "jsonschema-16.2.0-linux-x86_64/bin/jsonschema -d" in trace
    assert "-C " in trace
    assert " oras" in trace
    assert trace.index("probe:oras:version") < trace.index("cp:")
    assert trace.index("cp:") < trace.index("chown:root:root")
    for name in TOOLS:
        tool = Path(env["DEVFEATS_LIB_TEST_TOOL_DIR"]) / name
        assert tool.is_file()
        assert not tool.is_symlink()
        assert stat.S_IMODE(tool.stat().st_mode) == 0o555
    assert stat.S_IMODE(Path(env["DEVFEATS_LIB_TEST_TOOL_DIR"]).stat().st_mode) == 0o555


def test_installer_does_not_use_root_unreliable_writability_checks() -> None:
    installer = INSTALLER.read_text(encoding="utf-8")
    assert "test ! -w" not in installer
    assert "printf '%s\\n' '{\"value\":42}'" in installer
    assert 'chmod 0555 "$TOOL_DIR/jq"' in installer
    assert '"$TOOL_DIR/oras" "$TOOL_DIR"' in installer


@pytest.mark.parametrize(("pm", "expected_calls"), LINUX_PACKAGES.items())
def test_linux_installer_uses_exact_ordered_package_manager_commands(
    tmp_path: Path,
    pm: str,
    expected_calls: list[str],
) -> None:
    env = _harness(tmp_path, pm)
    assert _run_installer(env).returncode == 0
    trace = Path(env["TRACE"]).read_text(encoding="utf-8").splitlines()
    assert [line.removeprefix("pm:") for line in trace if line.startswith("pm:")] == (
        expected_calls
    )


def test_darwin_skips_linux_pm_uses_shasum_and_keeps_runner_ownership(
    tmp_path: Path,
) -> None:
    env = _harness(tmp_path, None, kernel="Darwin", machine="arm64")
    result = _run_installer(env)
    assert result.returncode == 0, result.stderr
    trace = Path(env["TRACE"]).read_text(encoding="utf-8")
    assert "pm:" not in trace
    assert trace.count("shasum:-a 256 -c") == 4
    assert "chown:" not in trace
    assert "brew:install flock gnupg xz" in trace
    assert "jq-macos-arm64" in trace
    assert "yq_darwin_arm64" in trace


def test_installer_accepts_shlock_as_the_only_lock_provider(tmp_path: Path) -> None:
    env = _harness(tmp_path, "apk", lock_provider="shlock")
    env["PM_PROVISION_LOCK"] = "0"
    result = _run_installer(env)
    assert result.returncode == 0, result.stderr


def test_apk_provisions_flock_instead_of_inheriting_it(tmp_path: Path) -> None:
    env = _harness(tmp_path, "apk")
    flock = Path(env["MOCK_BIN"]) / "flock"
    assert not flock.exists()
    result = _run_installer(env)
    assert result.returncode == 0, result.stderr
    assert flock.is_file()
    trace = Path(env["TRACE"]).read_text(encoding="utf-8")
    assert f"pm:{LINUX_PACKAGES['apk'][0]}" in trace


def test_installer_rejects_missing_lock_provider_before_download(
    tmp_path: Path,
) -> None:
    env = _harness(tmp_path, "apk", lock_provider=None)
    env["PM_PROVISION_LOCK"] = "0"
    result = _run_installer(env)
    assert result.returncode != 0
    assert "locking prerequisite (flock or shlock)" in result.stderr
    trace = Path(env["TRACE"]).read_text(encoding="utf-8")
    assert "curl:" not in trace


@pytest.mark.parametrize(("failures", "succeeds"), [(2, True), (3, False)])
def test_package_manager_retry_budget_is_exactly_three(
    tmp_path: Path,
    failures: int,
    succeeds: bool,  # noqa: FBT001 - injected positionally by pytest parametrization
) -> None:
    env = _harness(tmp_path, "apk")
    env["PM_FAILS"] = str(failures)
    result = _run_installer(env)
    assert (result.returncode == 0) is succeeds
    trace = Path(env["TRACE"]).read_text(encoding="utf-8")
    assert trace.count(f"pm:{LINUX_PACKAGES['apk'][0]}") == 3


@pytest.mark.parametrize(
    ("failure_asset", "expected_curls"),
    [("jqlang", 1), ("mikefarah", 2), ("sourcemeta", 3), ("oras-project", 4)],
)
def test_failing_curl_has_one_shell_invocation_per_reached_asset(
    tmp_path: Path,
    failure_asset: str,
    expected_curls: int,
) -> None:
    env = _harness(tmp_path, "apk")
    env["CURL_FAIL_MATCH"] = failure_asset
    result = _run_installer(env)
    assert result.returncode != 0
    curl_calls = [
        line
        for line in Path(env["TRACE"]).read_text(encoding="utf-8").splitlines()
        if line.startswith("curl:")
    ]
    assert len(curl_calls) == expected_curls
    assert all(
        "--retry 5 --retry-delay 2 --retry-connrefused" in call for call in curl_calls
    )
    assert sum(failure_asset in call for call in curl_calls) == 1


@pytest.mark.parametrize(
    (
        "kernel",
        "machine",
        "musl",
        "jq_asset",
        "yq_asset",
        "jsonschema_asset",
        "oras_asset",
        "hashes",
    ),
    [
        (
            "Linux",
            "x86_64",
            False,
            "jq-linux-amd64",
            "yq_linux_amd64",
            "jsonschema-16.2.0-linux-x86_64.zip",
            "oras_1.3.2_linux_amd64.tar.gz",
            (
                "b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f",
                "d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b",
                "6706cf6bd80d978ecbe0e3fbb7b44aee75a8bb6baa2ee5452dc55cb6c8f3e1be",
                "9229ccc6d17bb282039ad4a69abb16dcb887a5bce567c075d731d9b3c7ad8eaf",
            ),
        ),
        (
            "Linux",
            "aarch64",
            False,
            "jq-linux-arm64",
            "yq_linux_arm64",
            "jsonschema-16.2.0-linux-arm64.zip",
            "oras_1.3.2_linux_arm64.tar.gz",
            (
                "8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309",
                "03061b2a50c7a498de2bbb92d7cb078ce433011f085a4994117c2726be4106ea",
                "a7eb3f9005c065290514661fdedacf0e0f0bec05bcbe1fcc9600e3ba0de16ed9",
                "8db4a223bd6034deff198e791ea7cb3af0840df25b7e9f370e2f1f3fd20d389b",
            ),
        ),
        (
            "Linux",
            "x86_64",
            True,
            "jq-linux-amd64",
            "yq_linux_amd64",
            "jsonschema-16.2.0-linux-x86_64-musl.zip",
            "oras_1.3.2_linux_amd64.tar.gz",
            ("2296c08debdb471dcc5e35af2e4d6f6f6b27baa5e96db9cc65423bd7c2810f6c",),
        ),
        (
            "Linux",
            "aarch64",
            True,
            "jq-linux-arm64",
            "yq_linux_arm64",
            "jsonschema-16.2.0-linux-arm64-musl.zip",
            "oras_1.3.2_linux_arm64.tar.gz",
            ("bc9e27e33a13106e58bb000fafe8e47b95f8f8208481ea202d6ca916ffdb2a8e",),
        ),
        (
            "Darwin",
            "x86_64",
            False,
            "jq-macos-amd64",
            "yq_darwin_amd64",
            "jsonschema-16.2.0-darwin-x86_64.zip",
            "oras_1.3.2_darwin_amd64.tar.gz",
            (
                "e94b266e3c26690550006abe63152b782280f4e14374accdf04cbde844f00bc0",
                "616b0a0f6a5b79d746f05a169c2b9bb40dee00c605ef165b9a1c1681bba738ac",
                "44f5dfbba2a1f2bbf2d85b7c5b2cd5055a20d1a5656e602c6d146edea235ff5c",
                "2621f6b252b222f6fbf4e114d2fcaa0cec6b632624ffaf73143f66e4e0994f86",
            ),
        ),
        (
            "Darwin",
            "arm64",
            False,
            "jq-macos-arm64",
            "yq_darwin_arm64",
            "jsonschema-16.2.0-darwin-arm64.zip",
            "oras_1.3.2_darwin_arm64.tar.gz",
            (
                "2d75340ba57a4b4c8708a21c2dc8e958a48aaa8bba13b27f77f6e4c0eca07e",
                "541ba2287560df70f561955e2d7f7e1cd00cf2a15a884f6b5c87a4bfa887bc07",
                "95574d8ad36a30fb91967b056441a2b68c24d2441741b271544c3fb48a6c8f97",
                "7929f792cf272268412375ecad6f0fb3c20f164368d5b57966e67ad6d36eca53",
            ),
        ),
    ],
)
def test_installer_maps_platform_to_exact_official_assets_and_hashes(
    tmp_path: Path,
    kernel: str,
    machine: str,
    musl: bool,  # noqa: FBT001 - injected positionally by pytest parametrization
    jq_asset: str,
    yq_asset: str,
    jsonschema_asset: str,
    oras_asset: str,
    hashes: tuple[str, ...],
) -> None:
    env = _harness(
        tmp_path,
        None if kernel == "Darwin" else "apk",
        kernel=kernel,
        machine=machine,
        musl=musl,
    )
    result = _run_installer(env)
    assert result.returncode == 0, result.stderr
    trace = Path(env["TRACE"]).read_text(encoding="utf-8")
    for value in (jq_asset, yq_asset, jsonschema_asset, oras_asset, *hashes):
        assert value in trace


def test_installer_accepts_only_zypper_success_or_106(tmp_path: Path) -> None:
    for returncode, succeeds in ((0, True), (106, True), (7, False)):
        case = tmp_path / str(returncode)
        case.mkdir()
        env = _harness(case, "zypper")
        env["PM_RC"] = str(returncode)
        result = _run_installer(env)
        assert (result.returncode == 0) is succeeds


def test_installer_fails_before_extraction_install_or_probe_on_bad_checksum(
    tmp_path: Path,
) -> None:
    env = _harness(tmp_path, "apk")
    env["SHA_RC"] = "1"
    result = _run_installer(env)
    assert result.returncode != 0
    assert not Path(env["DEVFEATS_LIB_TEST_TOOL_DIR"]).exists()
    trace = Path(env["TRACE"]).read_text(encoding="utf-8")
    assert trace.count("curl:") == 4
    assert "unzip:" not in trace
    assert "tar:" not in trace
    assert "cp:" not in trace
    assert "probe:" not in trace


def test_installer_removes_partial_destination_when_finalization_fails(
    tmp_path: Path,
) -> None:
    env = _harness(tmp_path, "apk")
    env["CHOWN_RC"] = "9"
    result = _run_installer(env)
    assert result.returncode != 0
    assert not Path(env["DEVFEATS_LIB_TEST_TOOL_DIR"]).exists()
    trace = Path(env["TRACE"]).read_text(encoding="utf-8")
    assert "cp:" in trace
    assert "chown:" in trace


@pytest.mark.parametrize(
    ("kernel", "machine"), [("Linux", "riscv64"), ("FreeBSD", "x86_64")]
)
def test_installer_rejects_unsupported_platform_before_network(
    tmp_path: Path, kernel: str, machine: str
) -> None:
    env = _harness(tmp_path, "apk", kernel=kernel, machine=machine)
    result = _run_installer(env)
    assert result.returncode != 0
    trace = Path(env["TRACE"])
    assert not trace.exists() or "curl:" not in trace.read_text(encoding="utf-8")


def test_linux_installer_rejects_unsupported_package_manager(tmp_path: Path) -> None:
    env = _harness(tmp_path, None)
    result = _run_installer(env)
    assert result.returncode != 0
    assert not Path(env["TRACE"]).exists()


@pytest.mark.parametrize("tool_dir", ["relative", "/", "/var/empty/trailing/"])
def test_installer_rejects_unsafe_destination_before_network(
    tmp_path: Path, tool_dir: str
) -> None:
    env = _harness(tmp_path, "apk")
    env["DEVFEATS_LIB_TEST_TOOL_DIR"] = tool_dir
    result = _run_installer(env)
    assert result.returncode != 0
    trace_path = Path(env["TRACE"])
    assert not trace_path.exists() or "curl:" not in trace_path.read_text(
        encoding="utf-8"
    )


def test_installer_rejects_existing_or_symlink_destination(tmp_path: Path) -> None:
    for kind in ("directory", "symlink"):
        case = tmp_path / kind
        case.mkdir()
        env = _harness(case, "apk")
        destination = Path(env["DEVFEATS_LIB_TEST_TOOL_DIR"])
        if kind == "directory":
            destination.mkdir()
        else:
            target = case / "target"
            target.mkdir()
            destination.symlink_to(target, target_is_directory=True)
        result = _run_installer(env)
        assert result.returncode != 0
        trace_path = Path(env["TRACE"])
        assert not trace_path.exists() or "curl:" not in trace_path.read_text(
            encoding="utf-8"
        )


def test_installer_signal_trap_cleans_and_exits_nonzero(tmp_path: Path) -> None:
    env = _harness(tmp_path, "apk")
    curl = Path(env["PATH"]) / "curl"
    marker = tmp_path / "curl-started"
    env["SIGNAL_MARKER"] = str(marker)
    _script(curl, 'printf ready > "$SIGNAL_MARKER"\n/bin/sleep 60\n')
    process = subprocess.Popen(
        ["/bin/sh", str(INSTALLER)],
        env=env,
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    for _ in range(200):
        if marker.exists():
            break
        time.sleep(0.01)
    assert marker.exists()
    os.killpg(process.pid, signal.SIGTERM)
    assert process.wait(timeout=2) == 143
    assert not (tmp_path / "work").exists()
