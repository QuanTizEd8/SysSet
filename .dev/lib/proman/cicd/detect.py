"""Detect CI/CD workflow decisions from repository and event state.

This module replaces the shell-based `cicd_detect.sh` logic with Python while
preserving outputs and decision behavior expected by the GitHub Actions
workflows in this repository.

Responsibilities include:

- determining force-run mode for specific event conditions
- collecting changed files and mapping them to decision groups from YAML
- selecting feature and macOS test matrices
- enforcing PR version-bump rules for changed features
- resolving release eligibility and releasable feature list
- deciding devcontainer image build/reuse strategy
- computing all CI job configuration and emitting a single ``config`` JSON

The script writes a single ``config`` key to ``GITHUB_OUTPUT``.
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
from dataclasses import dataclass
from fnmatch import fnmatch
from pathlib import Path
from typing import TYPE_CHECKING

import yaml

from proman.config import load as load_config
from proman.git import git_repo_root
from proman.release.detect import detect_releasable
from proman.test.effective import load_effective
from proman.test.scenarios import (
    DEFAULT_MODES,
    expand_envs,
    iter_merged_scenarios,
)

if TYPE_CHECKING:
    from collections.abc import Iterable


FEATURE_DIRPATH = "features"

SELF_FILEPATH = Path(__file__).resolve()
_DETECT_REPO_RELPATH = ".dev/lib/proman/cicd/detect.py"


LOG = logging.getLogger("cicd_detect")


@dataclass(frozen=True)
class Env:
    """Environment and context values used by detection logic."""

    event_name: str
    ref_type: str
    ref_name: str
    head_ref: str
    base_ref: str
    before: str
    input_rebuild_devcontainer: str
    # Dispatch override inputs (empty string = not provided)
    input_run_lint: str
    input_run_validate: str
    input_run_unit: str
    input_run_install: str
    input_run_features: str
    input_features: str
    input_run_macos: str
    input_macos_features: str
    input_run_python: str
    input_run_docs: str
    input_run_features_devcontainer: str
    input_run_features_linux: str
    input_run_lib_linux: str
    input_run_lib_macos: str
    input_run_install_linux: str
    repo_owner: str
    repository: str
    repository_owner_type: str
    github_output: str


def sh(cmd: list[str], cwd: Path | None = None, *, check: bool = True) -> str:
    """Run a subprocess command and return stripped stdout.

    Parameters
    ----------
    cmd : list of str
        Command and arguments to execute.
    cwd : pathlib.Path or None, optional
        Working directory for command execution.
    check : bool, optional
        If True, raise on non-zero exit status.

    Returns
    -------
    str
        Standard output with surrounding whitespace removed.
    """
    proc = subprocess.run(
        cmd,
        cwd=str(cwd or git_repo_root()),
        check=check,
        text=True,
        capture_output=True,
    )
    return proc.stdout.strip()


def any_match(paths: Iterable[str], patterns: Iterable[str]) -> bool:
    """Return whether any path matches any provided pattern.

    Parameters
    ----------
    paths : iterable of str
        Changed file paths to test.
    patterns : iterable of str
        Glob-like matching patterns.

    Returns
    -------
    bool
        True if any path satisfies at least one pattern.
    """
    pats = list(patterns)
    if not pats:
        return False
    for p in paths:
        for pat in pats:
            if fnmatch(p, pat):
                return True
    return False


def discover_feature_ids() -> list[str]:
    """Discover feature IDs from feature metadata files.

    Returns
    -------
    list of str
        Sorted unique feature IDs inferred from ``features/*/metadata.yaml``.
    """
    ids: list[str] = []
    features_root = git_repo_root() / FEATURE_DIRPATH
    for metadata in sorted(features_root.glob("*/metadata.yaml")):
        rel = metadata.relative_to(features_root).as_posix()
        ids.append(rel.replace("/metadata.yaml", ""))
    return sorted(set(ids))


def compute_macos_matrix(feature_ids: list[str]) -> list[dict[str, str]]:
    """Compute ``{feature, runner, scenario}`` entries for macOS testing.

    Each macOS scenario becomes a separate matrix entry so that every scenario
    runs on its own fresh GHA runner, providing the same per-scenario isolation
    that Docker containers give Linux tests.

    Parameters
    ----------
    feature_ids : list of str
        Feature IDs to inspect. Only features with macOS scenarios are included.

    Returns
    -------
    list of dict
        ``{"feature": str, "runner": str, "scenario": str}`` entries, one per
        macOS scenario, sorted by feature then scenario key.
    """
    cfg = load_config()
    envs_data: dict = (
        yaml.safe_load(
            cfg.absolute_path("path.test_environments").read_text(encoding="utf-8"),
        )
        or {}
    )
    result: list[dict[str, str]] = []
    for fid in sorted(feature_ids):
        feat = cfg.absolute_path("path.test_features") / fid
        scenarios_file = feat / str(cfg["filename.feature_scenarios"])
        if not scenarios_file.exists():
            continue
        effective = load_effective(fid)
        for sc_name, merged in iter_merged_scenarios(
            effective.defaults,
            effective.scenarios,
        ):
            for key, env_name, _ in expand_envs(sc_name, merged):
                env_def = envs_data.get(env_name)
                if not isinstance(env_def, dict):
                    continue
                image = env_def.get("image", "")
                if image.startswith("macos"):
                    result.append({"feature": fid, "runner": image, "scenario": key})
    return result


def compute_feature_matrix(
    linux_ids: list[str],
    macos_ids: list[str],
) -> list[dict]:
    """Compute per-feature test configuration for the two-level matrix split.

    Returns one entry per feature with scenario lists for each platform.
    Features with no scenarios on any platform are omitted.

    Parameters
    ----------
    linux_ids : list of str
        Feature IDs to consider for devcontainer and standalone testing.
    macos_ids : list of str
        Feature IDs to consider for macOS testing.

    Returns
    -------
    list of dict
        ``{"feature": str, "devcontainer_scenarios": list[str],
        "linux_scenarios": list[str], "macos_scenarios": list[dict]}``
        entries sorted by feature name.
    """
    cfg = load_config()
    envs_data: dict = (
        yaml.safe_load(
            cfg.absolute_path("path.test_environments").read_text(encoding="utf-8"),
        )
        or {}
    )
    linux_set = set(linux_ids)
    macos_set = set(macos_ids)
    all_ids = sorted(linux_set | macos_set)
    result = []
    for fid in all_ids:
        feat = cfg.absolute_path("path.test_features") / fid
        scenarios_file = feat / str(cfg["filename.feature_scenarios"])
        if not scenarios_file.exists():
            continue
        effective = load_effective(fid)
        devcontainer_scenarios: list[str] = []
        linux_scenarios: list[str] = []
        macos_scenarios: list[dict[str, str]] = []
        for sc_name, merged in iter_merged_scenarios(
            effective.defaults,
            effective.scenarios,
        ):
            modes = merged.get("modes", list(DEFAULT_MODES))
            for key, env_name, _ in expand_envs(sc_name, merged):
                env_def = envs_data.get(env_name)
                if not isinstance(env_def, dict):
                    continue
                image = env_def.get("image", "")
                if image.startswith("macos"):
                    if fid in macos_set:
                        macos_scenarios.append({"scenario": key, "runner": image})
                elif fid in linux_set:
                    if modes != ["standalone"]:
                        devcontainer_scenarios.append(key)
                    if "standalone" in modes:
                        linux_scenarios.append(key)
        if not (devcontainer_scenarios or linux_scenarios or macos_scenarios):
            continue
        result.append(
            {
                "feature": fid,
                "devcontainer_scenarios": devcontainer_scenarios,
                "linux_scenarios": linux_scenarios,
                "macos_scenarios": macos_scenarios,
            },
        )
    return result


def select_feature_test_ids(
    changed: list[str],
    all_feature_ids: list[str],
    groups: dict[str, list[str]],
) -> tuple[list[str], list[str]]:
    """Select feature IDs for Linux and macOS scenario tests from changed paths.

    When ``scenario_test`` patterns match, all discovered features (and all
    macOS-capable features) are returned. Otherwise only features whose
    ``features/<id>/`` or ``test/features/<id>/`` paths changed are included.
    """
    macos_all = [d["feature"] for d in compute_macos_matrix(all_feature_ids)]
    if any_match(changed, groups["scenario_test"]):
        return sorted(all_feature_ids), sorted(macos_all)
    linux = sorted(
        f
        for f in all_feature_ids
        if any(p.startswith((f"features/{f}/", f"test/features/{f}/")) for p in changed)
    )
    macos = sorted(
        f
        for f in macos_all
        if any(p.startswith((f"features/{f}/", f"test/features/{f}/")) for p in changed)
    )
    return linux, macos


def merge_release_feature_test_ids(
    features_to_release: list[dict[str, str]],
    changed: list[str],
    all_feature_ids: list[str],
    groups: dict[str, list[str]],
) -> tuple[list[str], list[str]]:
    """Union releasable features with those touched by non-release path rules."""
    changed_linux, changed_macos = select_feature_test_ids(
        changed,
        all_feature_ids,
        groups,
    )
    released_set = {entry["feature"] for entry in features_to_release}
    macos_all_set = {d["feature"] for d in compute_macos_matrix(all_feature_ids)}
    linux = sorted(released_set | set(changed_linux))
    macos = sorted(set(changed_macos) | (released_set & macos_all_set))
    return linux, macos


def apply_dispatch_feature_matrix_filters(
    matrix: list[dict],
    *,
    run_devcontainer: bool,
    run_linux: bool,
) -> list[dict]:
    """Apply ``workflow_dispatch`` toggles for feature-test modalities.

    Parameters
    ----------
    matrix : list of dict
        Raw rows from :func:`compute_feature_matrix`.
    run_devcontainer : bool
        When false, devcontainer-mode scenarios are stripped.
    run_linux : bool
        When false, standalone Linux (ubuntu runner + DinD) scenarios are stripped.

    Returns
    -------
    list of dict
        Filtered matrix; rows with no scenarios left on any platform are dropped.
    """
    out: list[dict] = []
    for entry in matrix:
        dc = list(entry["devcontainer_scenarios"]) if run_devcontainer else []
        lx = list(entry["linux_scenarios"]) if run_linux else []
        mc = list(entry["macos_scenarios"])
        if not (dc or lx or mc):
            continue
        out.append(
            {
                **entry,
                "devcontainer_scenarios": dc,
                "linux_scenarios": lx,
                "macos_scenarios": mc,
            },
        )
    return out


def compute_unit_macos_matrix() -> list[dict]:
    """Compute macOS runner entries for unit tests.

    Returns
    -------
    list of dict
        One entry per macOS environment key in ``test/environments.yaml``
        (image name starts with ``"macos"``), preserving file order.
        Each entry has:
          - ``env``: environment key (display name)
          - ``runner``: GitHub Actions runner (= image name for macOS)
          - ``clean_path``: bool — strip PATH to system baseline before tests
          - ``path_prepend``: colon-separated dirs to prepend after clean_path stripping
          - ``integration``: bool — true when Homebrew is available (path_prepend set),
            meaning integration tests can run alongside unit tests
    """
    cfg = load_config()
    envs_data: dict = (
        yaml.safe_load(
            cfg.absolute_path("path.test_environments").read_text(encoding="utf-8"),
        )
        or {}
    )
    entries = []
    for env_key, val in envs_data.items():
        if not isinstance(val, dict):
            continue
        image = val.get("image", "")
        if not image.startswith("macos"):
            continue
        path_prepend = val.get("path_prepend", "")
        # Only include environments where Homebrew is available (path_prepend set).
        # Bare macOS environments (no path_prepend) are for feature tests only —
        # bootstrap functions cannot install tools without a package manager in PATH.
        if not path_prepend:
            continue
        entries.append(
            {
                "env": env_key,
                "runner": image,
                "clean_path": bool(val.get("clean_path", False)),
                "path_prepend": path_prepend,
                "integration": True,
            }
        )
    return entries


def compute_install_env_matrix() -> list[dict[str, str]]:
    """Compute Linux environment entries for install framework tests."""
    data: dict = (
        yaml.safe_load(
            load_config()
            .absolute_path("path.test_install_scenarios")
            .read_text(
                encoding="utf-8",
            ),
        )
        or {}
    )
    return [{"name": k, "env": v["env"]} for k, v in data.items() if k != "defaults"]


def compute_unit_env_matrix() -> list[dict[str, str]]:
    """Compute Linux environment entries for unit tests.

    Returns
    -------
    list of dict
        ``{"name": scenario_key, "env": env_name}`` for every non-``defaults``
        entry in ``test/lib/scenarios.yaml``, preserving file order.
    """
    data: dict = (
        yaml.safe_load(
            load_config()
            .absolute_path("path.test_lib_scenarios")
            .read_text(
                encoding="utf-8",
            ),
        )
        or {}
    )
    return [{"name": k, "env": v["env"]} for k, v in data.items() if k != "defaults"]


def _parse_feature_list(s: str) -> list[str]:
    r"""Parse a feature list from a dispatch input string.

    Parameters
    ----------
    s : str
        Either a JSON array string (``"[\"a\",\"b\"]"``) or a comma-separated
        list (``"a, b"``).

    Returns
    -------
    list of str
        Parsed feature IDs with empty strings filtered out.
    """
    s = s.strip()
    if s.startswith("["):
        return json.loads(s)
    return [f.strip() for f in s.split(",") if f.strip()]


def _bool_inp(val: str, *, default: bool = True) -> bool:
    """Convert a dispatch boolean input string to bool.

    Parameters
    ----------
    val : str
        ``"true"``, ``"false"``, or ``""`` (not provided).
    default : bool
        Value to return when ``val`` is empty.
    """
    if val == "":
        return default
    return val == "true"


def changed_files(env: Env) -> list[str]:
    """Collect changed files for the current event context.

    Parameters
    ----------
    env : Env
        Parsed environment/context values.

    Returns
    -------
    list of str
        Changed file paths according to event-specific diff baseline.
    """
    if env.event_name == "pull_request":
        out = sh(["git", "diff", "--name-only", f"origin/{env.base_ref}...HEAD"])
    else:
        out = sh(["git", "diff", "--name-only", f"{env.before}...HEAD"])
    return [line.strip() for line in out.splitlines() if line.strip()]


def detect_release(
    env: Env,
) -> tuple[bool, list[dict[str, str]], dict[str, str] | None]:
    """Resolve release mode, feature release entries, and library release entry.

    Parameters
    ----------
    env : Env
        Parsed environment/context values.

    Returns
    -------
    tuple
        Triple of:
        - ``is_release`` boolean
        - feature release entries as list of dicts (kind == "feature")
        - library release entry dict or None (kind == "lib")
    """
    is_release = False
    features_to_release: list[dict[str, str]] = []
    lib_release: dict[str, str] | None = None
    LOG.info(
        "release-gate: EVENT_NAME='%s' REF_TYPE='%s' REF_NAME='%s' BEFORE='%s'",
        env.event_name,
        env.ref_type,
        env.ref_name,
        env.before,
    )
    if env.event_name == "push" and env.ref_type == "branch" and env.ref_name == "main":
        LOG.info("release-gate: push-to-main detected; running detect_releasable().")
        root = git_repo_root()
        features_dir = root / "features"
        lib_metadata_path = root / "lib" / "metadata.yaml"
        try:
            all_releasable = detect_releasable(
                env.repository,
                features_dir,
                lib_metadata_path=lib_metadata_path,
            )
        except RuntimeError as exc:
            LOG.exception("release-gate: detect_releasable() failed")
            raise SystemExit(1) from exc
        features_to_release = [r for r in all_releasable if r.get("kind") != "lib"]
        lib_candidates = [r for r in all_releasable if r.get("kind") == "lib"]
        lib_release = lib_candidates[0] if lib_candidates else None
        LOG.info(
            "release-gate: detect_releasable() result: %s",
            all_releasable,
        )
        if all_releasable:
            is_release = True
    LOG.info(
        "release-gate: is_release='%s' features_count='%s' lib_release='%s'.",
        str(is_release).lower(),
        len(features_to_release),
        lib_release,
    )
    return is_release, features_to_release, lib_release


def head_feature_version(feature_id: str) -> str:
    """Read feature version from HEAD metadata.

    Parameters
    ----------
    feature_id : str
        Feature identifier path under ``features/``.

    Returns
    -------
    str
        Version string if present; otherwise an empty string.
    """
    p = git_repo_root() / FEATURE_DIRPATH / feature_id / "metadata.yaml"
    if not p.exists():
        return ""
    payload = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    version = payload.get("version", "")
    return str(version) if version is not None else ""


def base_feature_version(base_ref: str, feature_id: str) -> str:
    """Read feature version from the base branch metadata.

    Parameters
    ----------
    base_ref : str
        Pull request base ref (without ``origin/`` prefix).
    feature_id : str
        Feature identifier path under ``features/``.

    Returns
    -------
    str
        Version string if present in base; otherwise an empty string.
    """
    from gittidy import Git  # noqa: PLC0415

    content = Git(git_repo_root()).file_at_ref(
        f"origin/{base_ref}",
        f"features/{feature_id}/metadata.yaml",
        raise_missing=False,
    )
    if not content:
        return ""
    payload = yaml.safe_load(content) or {}
    version = payload.get("version", "")
    return str(version) if version is not None else ""


def enforce_version_bump(
    event_name: str,
    base_ref: str,
    changed: list[str],
    feature_ids: list[str],
) -> None:
    """Enforce version-bump policy for pull requests.

    Parameters
    ----------
    event_name : str
        Current GitHub event name.
    base_ref : str
        Pull request base ref.
    changed : list of str
        Changed file paths.
    feature_ids : list of str
        Feature IDs to evaluate.
    """
    if event_name != "pull_request":
        return
    libs_changed = any(p.startswith("lib/") for p in changed)
    bootstrap_changed = "features/install.sh" in changed
    needs_bump: list[str] = []

    for fid in feature_ids:
        fid_changed = any(p.startswith(f"features/{fid}/") for p in changed)
        if not (libs_changed or bootstrap_changed or fid_changed):
            continue
        base_v = base_feature_version(base_ref, fid)
        head_v = head_feature_version(fid)
        if not base_v:
            continue  # new feature exempt
        if base_v == head_v:
            needs_bump.append(f"{fid} (version still {head_v})")

    if needs_bump:
        LOG.error(
            "version-bump lint: modified features without metadata bump vs. origin/%s:",
            base_ref,
        )
        for item in needs_bump:
            LOG.error("  - %s", item)
        LOG.error(
            "   Bump the version field in each listed feature's"
            " metadata.yaml before merging.",
        )
        raise SystemExit(1)


def detect_devcontainer_changed(
    env: Env,
    *,
    is_first_push: bool,
    changed: list[str],
    groups: dict[str, list[str]],
) -> bool:
    """Decide whether devcontainer sources should be treated as changed.

    Parameters
    ----------
    env : Env
        Parsed environment/context values.
    is_first_push : bool
        True when this is the first push to a new branch (before == zero SHA).
        Workflow/detect-script changes do not trigger a devcontainer rebuild.
    changed : list of str
        Changed file paths.
    groups : dict of str to list of str
        Decision-group patterns.

    Returns
    -------
    bool
        True if devcontainer should be rebuilt due to changes or override.
    """
    if env.event_name == "workflow_dispatch":
        return env.input_rebuild_devcontainer == "true"
    if is_first_push:
        return True
    return any_match(changed, groups["devcontainer"])


def ghcr_tags(env: Env) -> list[str]:
    """Query existing devcontainer tags from GHCR.

    Parameters
    ----------
    env : Env
        Parsed environment/context values.

    Returns
    -------
    list of str
        Existing tag names if available; otherwise an empty list.
    """
    owner_name = env.repo_owner.lower()
    package_name = env.repository.split("/", 1)[1].lower()
    package_scope = ""
    owner_type = env.repository_owner_type
    if owner_type == "Organization":
        package_scope = f"orgs/{owner_name}"
    elif owner_type == "User":
        package_scope = f"users/{owner_name}"
    else:
        msg = f"Unsupported repository owner type for GHCR query: {owner_type}"
        raise RuntimeError(msg)
    if not package_scope:
        return []
    image_suffix = load_config()["ci"]["image"]["suffix"]
    try:
        out = sh(
            [
                "gh",
                "api",
                (
                    f"{package_scope}/packages/container"
                    f"/{package_name}{image_suffix}/versions"
                ),
                "--jq",
                ".[].metadata.container.tags[]",
            ],
        )
    except subprocess.CalledProcessError:
        return []
    return [line.strip() for line in out.splitlines() if line.strip()]


def write_outputs(path: str, outputs: dict[str, str]) -> None:
    """Append key-value outputs to GitHub Actions output file.

    Parameters
    ----------
    path : str
        Path to ``GITHUB_OUTPUT``.
    outputs : dict of str to str
        Output values to append.
    """
    with Path(path).open("a", encoding="utf-8") as f:
        f.writelines(f"{k}={v}\n" for k, v in outputs.items())


def _workflow_dispatch_input_str(raw: object, *, default: str = "") -> str:
    """Normalize ``workflow_dispatch`` input values for string-based parsing.

    GitHub may supply JSON booleans or strings; treat missing/``None`` as *default*.
    """
    if raw is None:
        return default
    if isinstance(raw, bool):
        return "true" if raw else "false"
    return str(raw)


def parse_env_from_context() -> Env:
    """Parse runtime environment from ``GITHUB_CONTEXT`` and process env vars.

    Returns
    -------
    Env
        Parsed environment object used for workflow detection.
    """
    github_ctx_raw = os.getenv("GITHUB_CONTEXT")
    if not github_ctx_raw:
        msg = "GITHUB_CONTEXT is required"
        raise SystemExit(msg)
    github_ctx = json.loads(github_ctx_raw)
    event = github_ctx["event"]
    repository_payload = event["repository"]
    repository_owner_payload = repository_payload["owner"]
    event_inputs = event.get("inputs") or {}
    return Env(
        event_name=str(github_ctx["event_name"]),
        ref_type=str(github_ctx["ref_type"]),
        ref_name=str(github_ctx["ref_name"]),
        head_ref=str(github_ctx.get("head_ref", "")),
        base_ref=str(github_ctx.get("base_ref", "")),
        before=str(event.get("before", "")),
        input_rebuild_devcontainer=_workflow_dispatch_input_str(
            event_inputs.get("rebuild_devcontainer"),
            default="false",
        ),
        input_run_lint=_workflow_dispatch_input_str(event_inputs.get("run_lint")),
        input_run_validate=_workflow_dispatch_input_str(
            event_inputs.get("run_validate")
        ),
        input_run_unit=_workflow_dispatch_input_str(event_inputs.get("run_unit")),
        input_run_install=_workflow_dispatch_input_str(event_inputs.get("run_install")),
        input_run_features=_workflow_dispatch_input_str(
            event_inputs.get("run_features")
        ),
        input_features=_workflow_dispatch_input_str(event_inputs.get("features")),
        input_run_macos=_workflow_dispatch_input_str(event_inputs.get("run_macos")),
        input_macos_features=_workflow_dispatch_input_str(
            event_inputs.get("macos_features")
        ),
        input_run_python=_workflow_dispatch_input_str(event_inputs.get("run_python")),
        input_run_docs=_workflow_dispatch_input_str(event_inputs.get("run_docs")),
        input_run_features_devcontainer=_workflow_dispatch_input_str(
            event_inputs.get("run_features_devcontainer"),
        ),
        input_run_features_linux=_workflow_dispatch_input_str(
            event_inputs.get("run_features_linux"),
        ),
        input_run_lib_linux=_workflow_dispatch_input_str(
            event_inputs.get("run_lib_linux")
        ),
        input_run_lib_macos=_workflow_dispatch_input_str(
            event_inputs.get("run_lib_macos")
        ),
        input_run_install_linux=_workflow_dispatch_input_str(
            event_inputs.get("run_install_linux"),
        ),
        repo_owner=str(github_ctx["repository_owner"]),
        repository=str(github_ctx["repository"]),
        repository_owner_type=str(repository_owner_payload["type"]),
        github_output=os.getenv("GITHUB_OUTPUT", ""),
    )


def build_config(  # noqa: PLR0913
    *,
    build_image: bool,
    image_name: str,
    image_tag: str,
    ci_image: str,
    run_lint: bool,
    run_validate: bool,
    run_unit: bool,
    run_install: bool,
    feature_matrix_raw: list[dict],
    run_python: bool,
    run_docs: bool,
    is_release: bool,
    features_to_release: list[dict[str, str]],
    unit_env_matrix: list[dict[str, str]],
    lib_release: dict[str, str] | None = None,
    unit_macos_matrix: list[dict[str, str]],
    install_env_matrix: list[dict[str, str]],
) -> dict:
    """Assemble the single ``config`` dict written to GITHUB_OUTPUT."""
    ci = load_config()["ci"]
    img = ci["image"]
    art = ci["artifacts"]
    pub = ci["publish"]
    scr = ci["scripts"]
    fds = ci["runner"]["free_disk_space"]
    source_enabled = any(
        [run_lint, run_validate, run_unit, run_install, bool(feature_matrix_raw)],
    )
    return {
        "build_devcontainer": {
            "enabled": build_image,
            "image_name": image_name,
            "image_tag": image_tag,
            "tag_is_latest": image_tag == "latest",
            "config_dir": img["config_dir"],
            "userdata_dir": img["userdata_dir"],
            "cache_ref_prefix": img["cache_ref_prefix"],
            "registry": pub["registry"],
            "build_matrix": img["build_matrix"],
        },
        "build_features": {
            "ci_image": ci_image,
            "enabled": source_enabled,
            "artifact_src": {
                "name": art["src"]["name"],
                "path": art["src"]["path"],
                "retention_days": art["retention_days"],
            },
            "artifact_dist": {
                "name": art["dist"]["name"],
                "path": art["dist"]["path"],
                "retention_days": art["retention_days"],
            },
        },
        "build_docs": {
            "ci_image": ci_image,
            "enabled": run_docs,
            "artifact": {
                "name": art["pages"]["name"],
                "path": art["pages"]["path"],
                "retention_days": art["retention_days"],
            },
        },
        "lint": {
            "ci_image": ci_image,
            "artifact_src_name": art["src"]["name"],
            "artifact_src_path": art["src"]["path"],
            "shell": {"enabled": run_lint},
            "validate": {"enabled": run_validate, "features_path": scr["features_src"]},
            "python": {"enabled": run_python},
        },
        "test_dev": {
            "enabled": run_python,
            "ci_image": ci_image,
        },
        "test_features": {
            "enabled": bool(feature_matrix_raw),
            "feature_matrix": [
                {
                    "feature": entry["feature"],
                    "artifact_src_name": art["src"]["name"],
                    "artifact_src_path": art["src"]["path"],
                    "ci_image": ci_image,
                    "registry": pub["registry"],
                    "free_disk_space": {
                        "min_avail_gb": fds["min_avail_gb"],
                        "tool_cache": fds["tool_cache"],
                        "swap_storage": fds["swap_storage"],
                        "docker_images": fds["docker_images"],
                        "android": fds["android"],
                        "dotnet": fds["dotnet"],
                        "haskell": fds["haskell"],
                        "large_packages": fds["large_packages"],
                    },
                    "devcontainer": {
                        "enabled": bool(entry["devcontainer_scenarios"]),
                        "scenarios": entry["devcontainer_scenarios"],
                    },
                    "linux": {
                        "enabled": bool(entry["linux_scenarios"]),
                        "scenarios": entry["linux_scenarios"],
                    },
                    "macos": {
                        "enabled": bool(entry["macos_scenarios"]),
                        "scenarios": entry["macos_scenarios"],
                    },
                }
                for entry in feature_matrix_raw
            ],
        },
        "test_lib": {
            "enabled": run_unit and (bool(unit_env_matrix) or bool(unit_macos_matrix)),
            "linux_enabled": bool(unit_env_matrix),
            "macos_enabled": bool(unit_macos_matrix),
            "ci_image": ci_image,
            "artifact_dist_name": art["dist"]["name"],
            "artifact_dist_path": art["dist"]["path"],
            "linux_matrix": unit_env_matrix,
            "macos_matrix": unit_macos_matrix,
        },
        "test_install": {
            "enabled": run_install and bool(install_env_matrix),
            "linux_enabled": bool(install_env_matrix),
            "ci_image": ci_image,
            "artifact_src_name": art["src"]["name"],
            "artifact_src_path": art["src"]["path"],
            "linux_matrix": install_env_matrix,
        },
        "deploy": {
            "enabled": is_release,
            "features": features_to_release,
            "lib_release": {
                "enabled": lib_release is not None,
                "version": lib_release["version"] if lib_release else "",
                "tag": lib_release["tag"] if lib_release else "",
            },
            "artifact_src_name": art["src"]["name"],
            "artifact_src_path": art["src"]["path"],
            "artifact_dist_name": art["dist"]["name"],
            "artifact_dist_path": art["dist"]["path"],
            "features_src_path": scr["features_src"],
            "registry": pub["registry"],
            "git_bot_name": pub["git_bot"]["name"],
            "git_bot_email": pub["git_bot"]["email"],
            "pages_environment": pub["pages_environment"],
        },
    }


def main() -> None:
    """Entrypoint for CI/CD detection script execution."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    env = parse_env_from_context()
    if not env.github_output:
        msg = "GITHUB_OUTPUT is required"
        raise SystemExit(msg)
    LOG.info(
        "context: event='%s' ref_type='%s' ref_name='%s' head_ref='%s' base_ref='%s'",
        env.event_name,
        env.ref_type,
        env.ref_name,
        env.head_ref,
        env.base_ref,
    )

    groups = load_config()["ci"]["triggers"]
    LOG.info("groups: loaded decision groups: %s", ", ".join(sorted(groups.keys())))

    changed = changed_files(env)
    LOG.info(
        "Changed files: %s",
        json.dumps(changed, indent=4) if changed else "none",
    )

    zero_sha = "0" * 40
    is_first_push = env.event_name == "push" and env.before == zero_sha
    is_force = env.event_name != "workflow_dispatch" and (
        is_first_push
        or any_match(
            changed,
            [
                ".github/workflows/*.yaml",
                _DETECT_REPO_RELPATH,
            ],
        )
    )
    LOG.info(
        "force-gate: is_force='%s' is_first_push='%s'",
        str(is_force).lower(),
        str(is_first_push).lower(),
    )

    all_feature_ids = discover_feature_ids()
    LOG.info("features: discovered total='%s'", len(all_feature_ids))

    is_release, features_to_release, lib_release = detect_release(env)

    # ── Resolve run flags ────────────────────────────────────────────────────
    if env.event_name == "workflow_dispatch":
        run_lint = _bool_inp(env.input_run_lint)
        run_validate = _bool_inp(env.input_run_validate)
        run_unit = _bool_inp(env.input_run_unit)
        run_install = _bool_inp(env.input_run_install)
        run_features_flag = _bool_inp(env.input_run_features)
        run_macos_flag = _bool_inp(env.input_run_macos)
        run_python = _bool_inp(env.input_run_python)
        run_docs = _bool_inp(env.input_run_docs)
        features: list[str] = (
            _parse_feature_list(env.input_features)
            if env.input_features
            else (all_feature_ids if run_features_flag else [])
        )
        macos_capable_ids: list[str] = (
            _parse_feature_list(env.input_macos_features)
            if env.input_macos_features
            else (
                [d["feature"] for d in compute_macos_matrix(all_feature_ids)]
                if run_macos_flag
                else []
            )
        )
        LOG.info(
            "dispatch: run_lint=%s run_validate=%s run_unit=%s run_install=%s"
            " run_features=%s run_macos=%s run_python=%s run_docs=%s",
            run_lint,
            run_validate,
            run_unit,
            run_install,
            run_features_flag,
            run_macos_flag,
            run_python,
            run_docs,
        )
    elif is_force:
        run_lint = run_validate = run_unit = run_install = run_python = run_docs = True
        features = all_feature_ids
        macos_capable_ids = [
            d["feature"] for d in compute_macos_matrix(all_feature_ids)
        ]
        LOG.info("force-gate: all jobs enabled; all features selected")
    elif is_release:
        run_lint = run_validate = run_unit = run_install = run_python = run_docs = True
        features, macos_capable_ids = merge_release_feature_test_ids(
            features_to_release,
            changed,
            all_feature_ids,
            groups,
        )
        LOG.info(
            "release-gate: all jobs enabled; testing releasable + changed features: %s",
            features,
        )
    else:
        run_lint = any_match(changed, groups["lint"])
        run_validate = any_match(changed, groups["validate"])
        run_unit = any_match(changed, groups["unit_test"])
        run_install = any_match(changed, groups["install_test"])
        run_docs = any_match(changed, groups["docs"])
        run_python = any_match(changed, groups["python_test"])

        features, macos_capable_ids = select_feature_test_ids(
            changed,
            all_feature_ids,
            groups,
        )

    LOG.info(
        "decision: run_lint='%s' run_validate='%s' run_unit='%s' run_install='%s'"
        " run_python='%s' run_docs='%s'",
        str(run_lint).lower(),
        str(run_validate).lower(),
        str(run_unit).lower(),
        str(run_install).lower(),
        str(run_python).lower(),
        str(run_docs).lower(),
    )

    # ── Compute matrices ─────────────────────────────────────────────────────
    feature_matrix_raw = compute_feature_matrix(features, macos_capable_ids)

    unit_env_matrix = compute_unit_env_matrix()
    unit_macos_matrix = compute_unit_macos_matrix()
    install_env_matrix = compute_install_env_matrix()

    if env.event_name == "workflow_dispatch":
        run_dc = _bool_inp(env.input_run_features_devcontainer)
        run_lx = _bool_inp(env.input_run_features_linux)
        run_lib_lx = _bool_inp(env.input_run_lib_linux)
        run_lib_mc = _bool_inp(env.input_run_lib_macos)
        run_install_lx = _bool_inp(env.input_run_install_linux)
        LOG.info(
            "dispatch: modality_filters features_devcontainer='%s' features_linux='%s'"
            " lib_linux='%s' lib_macos='%s' install_linux='%s'",
            str(run_dc).lower(),
            str(run_lx).lower(),
            str(run_lib_lx).lower(),
            str(run_lib_mc).lower(),
            str(run_install_lx).lower(),
        )
        feature_matrix_raw = apply_dispatch_feature_matrix_filters(
            feature_matrix_raw,
            run_devcontainer=run_dc,
            run_linux=run_lx,
        )
        if not run_lib_lx:
            unit_env_matrix = []
        if not run_lib_mc:
            unit_macos_matrix = []
        if not run_install_lx:
            install_env_matrix = []

    LOG.info(
        "matrices: features=%d feature_matrix=%d unit_env=%d "
        "unit_macos=%d install_env=%d",
        len(features),
        len(feature_matrix_raw),
        len(unit_env_matrix),
        len(unit_macos_matrix),
        len(install_env_matrix),
    )

    enforce_version_bump(env.event_name, env.base_ref, changed, all_feature_ids)

    # ── Devcontainer image gate ───────────────────────────────────────────────
    devcontainer_changed = detect_devcontainer_changed(
        env,
        is_first_push=is_first_push,
        changed=changed,
        groups=groups,
    )
    existing_tags = ghcr_tags(env)
    has_latest = "latest" in existing_tags

    branch_name = env.head_ref or env.ref_name
    branch_tag = "branch-" + re.sub(r"[^a-zA-Z0-9._-]", "-", branch_name)
    has_branch = branch_tag in existing_tags

    LOG.info(
        "image-gate: devcontainer_changed='%s' existing_tags_count='%s'"
        " has_latest='%s' has_branch='%s'",
        str(devcontainer_changed).lower(),
        len(existing_tags),
        str(has_latest).lower(),
        str(has_branch).lower(),
    )

    build_image = False
    image_tag = "latest"
    if branch_name == "main":
        image_tag = "latest"
        if devcontainer_changed or not has_latest:
            build_image = True
    elif devcontainer_changed:
        build_image = True
        image_tag = branch_tag
    elif has_branch:
        build_image = False
        image_tag = branch_tag
    elif has_latest:
        build_image = False
        image_tag = "latest"
    else:
        build_image = True
        image_tag = branch_tag

    LOG.info(
        "image-gate: final build_image='%s' image_tag='%s'",
        str(build_image).lower(),
        image_tag,
    )

    # ── Assemble and emit single config output ────────────────────────────────
    ci_cfg = load_config()["ci"]
    image_name = (
        f"{ci_cfg['publish']['registry']}/{env.repository.lower()}"
        f"{ci_cfg['image']['suffix']}"
    )
    ci_image = f"{image_name}:{image_tag}"

    config = build_config(
        build_image=build_image,
        image_name=image_name,
        image_tag=image_tag,
        ci_image=ci_image,
        run_lint=run_lint,
        run_validate=run_validate,
        run_unit=run_unit,
        run_install=run_install,
        feature_matrix_raw=feature_matrix_raw,
        run_python=run_python,
        run_docs=run_docs,
        is_release=is_release,
        features_to_release=features_to_release,
        lib_release=lib_release,
        unit_env_matrix=unit_env_matrix,
        unit_macos_matrix=unit_macos_matrix,
        install_env_matrix=install_env_matrix,
    )

    write_outputs(
        env.github_output,
        {"config": json.dumps(config, separators=(",", ":"))},
    )
    LOG.info(
        "output: wrote config to GITHUB_OUTPUT (keys: %s)",
        ", ".join(config.keys()),
    )


if __name__ == "__main__":
    main()
