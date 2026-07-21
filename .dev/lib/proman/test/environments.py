"""Build and resolve Docker environments for devcontainer tests."""

from __future__ import annotations

import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path, PurePosixPath
from typing import TYPE_CHECKING, TextIO

import yaml

from proman.config import load as load_config

if TYPE_CHECKING:
    import threading
    from collections.abc import Callable

_DOCKER_GITHUB_ARG_LINES = "ARG GITHUB_TOKEN\nENV GITHUB_TOKEN=${GITHUB_TOKEN}\n"
_BUILDKIT_PROGRESS_PLAIN = "plain"
_RUN_FRAGMENT_PATH_RE = re.compile(
    r"^[A-Za-z0-9_-][A-Za-z0-9_.-]*(/[A-Za-z0-9_-][A-Za-z0-9_.-]*)*$"
)

# POSIX sh retry helper injected into every env-bootstrap / scenario `setup:`
# shell context (Dockerfile RUN heredocs, standalone `sh -c`, macOS `bash -c`).
# None of those contexts source lib/net.bash (no repo checkout yet, or a bare
# base-image shell), so package-manager calls (apt-get/dnf/pacman/...) have no
# access to curl's own transient-error retry — this is a blind, bounded retry
# (3 attempts, 5s delay) rather than curl's smarter classification, since
# package managers have no equivalent "transient vs permanent" signal to key
# off. Not `local`-free-POSIX pedantic, but works under dash/ash/bash alike.
RETRY_SHELL_PREAMBLE = """\
retry() {
  _devfeats_retry_n=0
  while [ "$_devfeats_retry_n" -lt 3 ]; do
    "$@" && return 0
    _devfeats_retry_n=$((_devfeats_retry_n + 1))
    [ "$_devfeats_retry_n" -lt 3 ] && sleep 5
  done
  return 1
}
"""


def _try_run(
    cmd: list[str],
    kwargs: dict[str, object],
) -> subprocess.CompletedProcess | subprocess.CalledProcessError:
    """One subprocess.run(cmd, check=True) attempt; failure is returned, not raised."""
    try:
        return subprocess.run(cmd, check=True, **kwargs)
    except subprocess.CalledProcessError as exc:
        return exc


def run_with_retry(
    cmd: list[str],
    *,
    attempts: int = 3,
    delay: float = 5,
    output: TextIO | None = None,
    cancel_event: threading.Event | None = None,
    process_started: Callable[[subprocess.Popen[str]], None] | None = None,
    process_finished: Callable[[subprocess.Popen[str]], None] | None = None,
    **kwargs: object,
) -> subprocess.CompletedProcess:
    """subprocess.run(cmd, check=True, **kwargs), retrying transient failures.

    Docker build/run/login failures are usually a registry pull blip, not a
    deterministic bug, so a small bounded retry (unlike lib/net.bash's 60x for
    a single curl request) is worth it here — these are expensive operations,
    not lightweight HTTP fetches.
    """
    result: subprocess.CompletedProcess | subprocess.CalledProcessError
    for attempt in range(1, attempts + 1):
        if cancel_event is None:
            result = _try_run(cmd, kwargs)
        else:
            if (
                kwargs.get("stdout") is subprocess.PIPE
                or kwargs.get("stderr") is subprocess.PIPE
                or kwargs.get("capture_output")
            ):
                message = "Cancellable commands require non-PIPE output streams."
                raise ValueError(message)
            if cancel_event.is_set():
                message = "Command cancelled before launch."
                raise InterruptedError(message)
            proc = subprocess.Popen(cmd, start_new_session=os.name == "posix", **kwargs)
            if process_started is not None:
                process_started(proc)
            try:
                while True:
                    returncode = proc.poll()
                    if returncode is not None:
                        break
                    if cancel_event.wait(0.05):
                        _terminate_process_group(proc)
                        message = "Command cancelled."
                        raise InterruptedError(message)
                result = subprocess.CompletedProcess(cmd, returncode)
                if returncode:
                    result = subprocess.CalledProcessError(returncode, cmd)
            finally:
                if process_finished is not None:
                    process_finished(proc)
        if isinstance(result, subprocess.CompletedProcess):
            return result
        if attempt < attempts:
            message = (
                f"⚠️  command failed (attempt {attempt}/{attempts}); "
                f"retrying in {delay}s: {' '.join(cmd)}\n"
            )
            if output is None:
                print(message, end="", file=sys.stderr)
            else:
                output.write(message)
                output.flush()
            if cancel_event is None:
                time.sleep(delay)
            elif cancel_event.wait(delay):
                message = "Command cancelled while waiting to retry."
                raise InterruptedError(message)
    raise result


def _terminate_process_group(proc: subprocess.Popen[str]) -> None:
    """Terminate a subprocess and descendants started in their own POSIX session."""
    if proc.poll() is not None:
        return
    try:
        if os.name == "posix":
            os.killpg(proc.pid, signal.SIGTERM)
        else:
            proc.terminate()
        proc.wait(timeout=1)
    except ProcessLookupError:
        return
    except subprocess.TimeoutExpired:
        try:
            if os.name == "posix":
                os.killpg(proc.pid, signal.SIGKILL)
            else:
                proc.kill()
        except ProcessLookupError:
            return
        proc.wait(timeout=1)


def docker_buildkit_env(base: dict[str, str] | None = None) -> dict[str, str]:
    """Return env for test Docker builds: BuildKit enabled, plain progress output."""
    env = dict(base if base is not None else os.environ)
    env["DOCKER_BUILDKIT"] = "1"
    env["BUILDKIT_PROGRESS"] = _BUILDKIT_PROGRESS_PLAIN
    return env


def load(path: Path | str) -> dict:
    """Load an environments YAML file and return its contents as a dict."""
    return yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}


def _validated_image(env_name: str, env: dict) -> str | None:
    """Return an optional non-empty image string, rejecting explicit nulls."""
    if "image" not in env:
        return None
    image = env["image"]
    if not isinstance(image, str) or not image:
        message = f"Environment {env_name!r} image must be a non-empty string."
        raise ValueError(message)
    return image


def is_macos(env_name: str, envs: dict) -> bool:
    """Return whether the nearest image in an environment chain is macOS."""
    seen: set[str] = set()
    cursor: str | None = env_name
    while cursor is not None:
        if cursor in seen:
            message = f"Environment {env_name!r} has a cyclic from chain at {cursor!r}."
            raise ValueError(message)
        seen.add(cursor)
        env = envs.get(cursor)
        if not isinstance(env, dict):
            message = f"Environment {cursor!r} is missing or is not a mapping."
            raise ValueError(message)  # noqa: TRY004 - invalid config value
        image = _validated_image(cursor, env)
        if image is not None:
            return bool(re.match(r"^macos", image))
        parent = env.get("from")
        if parent is not None and (not isinstance(parent, str) or not parent):
            message = f"Environment {cursor!r} from must be a non-empty string."
            raise ValueError(message)
        cursor = parent
    message = f"Environment {env_name!r} does not resolve to an image."
    raise ValueError(message)


def resolve_attributes(env_name: str, envs: dict) -> dict:
    """Flatten `attributes:` down an environment's `from:` chain.

    Mirrors `_collect_layers`'s recursive flattening, but for the WhenSpec-style
    `os.*`/`plat.*` attribute facts instead of Dockerfile bodies: a variant with
    no `attributes:` of its own inherits its parent's untouched; one that
    declares its own merges on top (only meaningful for a variant that
    genuinely changes OS identity, which none do today).
    """
    env = envs[env_name]
    from_env = env.get("from")
    inherited = resolve_attributes(from_env, envs) if from_env else {}
    return {**inherited, **env.get("attributes", {})}


def _validate_build(env_name: str, env: dict, *, native_macos: bool) -> dict:
    """Validate and return one environment's optional build declaration."""
    if "build" not in env:
        return {}
    build = env["build"]
    if not isinstance(build, dict):
        message = f"Environment {env_name!r} build must be a mapping."
        raise ValueError(message)  # noqa: TRY004 - invalid config value
    unknown = set(build) - {"dockerfile", "runFragmentPath", "resolveAttempts"}
    if unknown:
        message = (
            f"Environment {env_name!r} build has unknown keys: "
            f"{', '.join(sorted(unknown))}."
        )
        raise ValueError(message)
    sources = [key for key in ("dockerfile", "runFragmentPath") if key in build]
    if len(sources) != 1:
        message = (
            f"Environment {env_name!r} build must declare exactly one of "
            "dockerfile or runFragmentPath."
        )
        raise ValueError(message)
    if sources[0] == "dockerfile":
        commands = build["dockerfile"]
        if not isinstance(commands, str) or not commands.strip():
            message = f"Environment {env_name!r} dockerfile shell commands are empty."
            raise ValueError(message)
    elif native_macos:
        message = (
            f"Environment {env_name!r} uses runFragmentPath, which is unsupported "
            "for native macOS environments."
        )
        raise ValueError(message)
    attempts = build.get("resolveAttempts", 3)
    if (
        not isinstance(attempts, int)
        or isinstance(attempts, bool)
        or attempts < 1
        or attempts > 3
    ):
        message = (
            f"Environment {env_name!r} build.resolveAttempts must be an integer "
            "from 1 through 3."
        )
        raise ValueError(message)
    return build


def validate_environment_chain(
    env_name: str,
    envs: dict,
    *,
    native_macos: bool | None = None,
) -> tuple[str, ...]:
    """Validate a complete ``from:`` chain and return it root-first."""
    if env_name not in envs:
        message = f"Unknown environment: {env_name!r}"
        raise ValueError(message)
    if native_macos is None:
        native_macos = is_macos(env_name, envs)
    chain: list[str] = []
    seen: set[str] = set()
    cursor: str | None = env_name
    while cursor is not None:
        if cursor in seen:
            message = f"Environment {env_name!r} has a cyclic from chain at {cursor!r}."
            raise ValueError(message)
        seen.add(cursor)
        env = envs.get(cursor)
        if not isinstance(env, dict):
            message = f"Environment {cursor!r} is missing or is not a mapping."
            raise ValueError(message)  # noqa: TRY004 - invalid config value
        _validated_image(cursor, env)
        _validate_build(cursor, env, native_macos=native_macos)
        chain.append(cursor)
        parent = env.get("from")
        if parent is not None and (not isinstance(parent, str) or not parent):
            message = f"Environment {cursor!r} from must be a non-empty string."
            raise ValueError(message)
        cursor = parent
    chain.reverse()
    return tuple(chain)


def macos_build_commands(env_name: str, envs: dict) -> str:
    """Return validated native macOS bootstrap commands in inheritance order."""
    chain = validate_environment_chain(env_name, envs, native_macos=True)
    commands = [
        envs[name]["build"]["dockerfile"].strip()
        for name in chain
        if "build" in envs[name]
    ]
    return "\n".join(commands)


def _resolve_attempts(env_name: str, envs: dict) -> int:
    """Return the most-derived explicit Docker build retry budget."""
    cursor: str | None = env_name
    while cursor is not None:
        env = envs[cursor]
        build = env.get("build", {})
        if "resolveAttempts" in build:
            return build["resolveAttempts"]
        cursor = env.get("from")
    return 3


def _collect_layers(
    env_name: str,
    envs: dict,
    envs_dir: Path,
    child_args: dict | None = None,
) -> tuple[str, str, dict]:
    """Flatten the from: chain into (base_image, dockerfile_body, build_args).

    base_image: root ancestor's image field.
    dockerfile_body: everything after the FROM line (excluding the GITHUB_TOKEN lines).
    build_args: all {KEY: VALUE} pairs from args: fields in the chain, to pass as
                --build-arg (standalone) or build.args (devcontainer).

    child_args: {KEY: VALUE} dict passed by the immediate child env via args:.
    """
    env = envs[env_name]
    from_env = env.get("from")
    image = env.get("image")
    build = _validate_build(env_name, env, native_macos=False)
    df_inline = build.get("dockerfile")
    fragment_path = build.get("runFragmentPath")
    env_vars = env.get("env_vars", {})
    my_args = env.get("args", {})  # args THIS level passes UP to its parent

    if from_env:
        base_image, body, build_args = _collect_layers(
            from_env,
            envs,
            envs_dir,
            child_args=my_args,
        )
    else:
        base_image, body, build_args = image, "", {}

    # Merge what our child gave us into the accumulated build_args
    if child_args:
        build_args = {**build_args, **child_args}

    # ARG lines for child_args — inserted before this layer's RUN block
    arg_lines = "".join(f"ARG {k}\n" for k in (child_args or {}))

    if fragment_path:
        raw = _load_run_fragment(envs_dir, fragment_path)
        delimiter = _heredoc_delimiter(raw)
        body += f"{arg_lines}RUN <<'{delimiter}'\nset -eux\n{RETRY_SHELL_PREAMBLE}{raw}"
        if not raw.endswith("\n"):
            body += "\n"
        body += f"{delimiter}\n"
    elif df_inline is not None:
        commands = df_inline.strip()
        delimiter = _heredoc_delimiter(commands)
        body += (
            f"{arg_lines}RUN <<'{delimiter}'\nset -eux\n"
            f"{RETRY_SHELL_PREAMBLE}{commands}\n{delimiter}\n"
        )

    if env_vars:
        body += "".join(f"ENV {k}={v}\n" for k, v in env_vars.items())

    return base_image, body, build_args


def _load_run_fragment(envs_dir: Path, value: object) -> str:
    """Load a contained LF-only UTF-8 shell fragment without normalizing it."""
    if not isinstance(value, str) or not value:
        message = "runFragmentPath must be a non-empty relative path."
        raise ValueError(message)
    posix_relative = PurePosixPath(value)
    if (
        "\\" in value
        or _RUN_FRAGMENT_PATH_RE.fullmatch(value) is None
        or posix_relative.is_absolute()
        or posix_relative.as_posix() != value
        or any(part in {"", ".", ".."} for part in posix_relative.parts)
    ):
        message = (
            f"Invalid runFragmentPath {value!r}: path must be normalized and relative."
        )
        raise ValueError(message)
    relative = Path(*posix_relative.parts)
    root = envs_dir.resolve()
    candidate = envs_dir / relative
    cursor = envs_dir
    for part in relative.parts:
        cursor /= part
        if cursor.is_symlink():
            message = (
                f"Invalid runFragmentPath {value!r}: symlink path components "
                "are not allowed."
            )
            raise ValueError(message)
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        message = (
            f"Invalid runFragmentPath {value!r}: file is missing or outside test/envs."
        )
        raise ValueError(message) from exc
    if candidate.is_symlink() or not resolved.is_file():
        message = (
            f"Invalid runFragmentPath {value!r}: expected a regular non-symlink file."
        )
        raise ValueError(message)

    raw = resolved.read_bytes()
    if b"\0" in raw or b"\r" in raw:
        message = (
            f"Invalid runFragmentPath {value!r}: file must be LF-only UTF-8 text "
            "without NUL bytes."
        )
        raise ValueError(message)
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        message = f"Invalid runFragmentPath {value!r}: file must be UTF-8 text."
        raise ValueError(message) from exc


def _heredoc_delimiter(content: str) -> str:
    """Choose a Dockerfile heredoc delimiter absent as an exact content line."""
    lines = set(content.splitlines())
    index = 0
    while True:
        suffix = "" if index == 0 else f"_{index}"
        delimiter = f"DEVFEATS_RUN_FRAGMENT{suffix}"
        if delimiter not in lines:
            return delimiter
        index += 1


def resolve(
    env_name: str,
    envs: dict,
    scenario_args: dict | None = None,
    scenario_env_vars: dict | None = None,
    *,
    output: TextIO | None = None,
    cancel_event: threading.Event | None = None,
    process_started: Callable[[subprocess.Popen[str]], None] | None = None,
    process_finished: Callable[[subprocess.Popen[str]], None] | None = None,
) -> str:
    """Resolve an environment name to a Docker image tag, building if needed."""
    env = envs.get(env_name)
    if env is None:
        message = f"Unknown environment: {env_name!r}"
        raise ValueError(message)

    native_macos = is_macos(env_name, envs)
    chain = validate_environment_chain(env_name, envs, native_macos=native_macos)
    if native_macos:
        return next(
            envs[name]["image"] for name in reversed(chain) if "image" in envs[name]
        )

    envs_dir = load_config().absolute_path("path.test_envs")
    base_image, body, build_args = _collect_layers(
        env_name,
        envs,
        envs_dir,
        child_args=scenario_args or None,
    )

    if scenario_env_vars:
        body += "".join(f"ENV {k}={v}\n" for k, v in scenario_env_vars.items())

    if not body and not build_args:
        return base_image  # fast path: nothing to build

    safe_name = re.sub(r"[^a-zA-Z0-9_.\-]", "-", env_name)
    if scenario_args or scenario_env_vars:
        h = hashlib.sha256(
            json.dumps(
                {"a": scenario_args or {}, "e": scenario_env_vars or {}},
                sort_keys=True,
            ).encode(),
        ).hexdigest()[:8]
        tag = f"devfeats-env-{safe_name}-{h}:latest"
    else:
        tag = f"devfeats-env-{safe_name}:latest"

    envs_dir.mkdir(parents=True, exist_ok=True)
    dockerfile_content = f"FROM {base_image}\n{_DOCKER_GITHUB_ARG_LINES}{body}"

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".Dockerfile",
        dir=envs_dir,
        delete=False,
    ) as tf:
        tf.write(dockerfile_content)
        df_tmp = tf.name

    try:
        cmd = [
            "docker",
            "build",
            "--progress",
            _BUILDKIT_PROGRESS_PLAIN,
            "-t",
            tag,
            "-f",
            df_tmp,
            str(envs_dir),
        ]
        for k, v in build_args.items():
            cmd.extend(["--build-arg", f"{k}={v}"])
        run_kwargs: dict[str, object] = {"env": docker_buildkit_env()}
        if output is not None:
            run_kwargs.update(
                stdout=output,
                stderr=subprocess.STDOUT,
                text=True,
            )
        run_with_retry(
            cmd,
            attempts=_resolve_attempts(env_name, envs),
            output=output,
            cancel_event=cancel_event,
            process_started=process_started,
            process_finished=process_finished,
            **run_kwargs,
        )
    finally:
        Path(df_tmp).unlink(missing_ok=True)

    return tag


def resolve_cli() -> None:
    """Parse CLI arguments and print the resolved Docker image tag."""
    env_name: str | None = None
    scenario_args: dict = {}
    scenario_env_vars: dict = {}

    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg in ("--arg", "--env-var"):
            if i + 1 >= len(sys.argv):
                print(
                    "usage: proman-test-resolve-env <env-name>"
                    " [--arg KEY=VALUE ...] [--env-var KEY=VALUE ...]",
                    file=sys.stderr,
                )
                sys.exit(1)
            k, _, v = sys.argv[i + 1].partition("=")
            if arg == "--arg":
                scenario_args[k] = v
            else:
                scenario_env_vars[k] = v
            i += 2
        elif not arg.startswith("--") and env_name is None:
            env_name = arg
            i += 1
        else:
            print(
                "usage: proman-test-resolve-env <env-name>"
                " [--arg KEY=VALUE ...] [--env-var KEY=VALUE ...]",
                file=sys.stderr,
            )
            sys.exit(1)

    if env_name is None:
        print(
            "usage: proman-test-resolve-env <env-name>"
            " [--arg KEY=VALUE ...] [--env-var KEY=VALUE ...]",
            file=sys.stderr,
        )
        sys.exit(1)

    envs = load(load_config().absolute_path("path.test_environments"))
    print(
        resolve(
            env_name,
            envs,
            scenario_args=scenario_args or None,
            scenario_env_vars=scenario_env_vars or None,
        ),
    )
