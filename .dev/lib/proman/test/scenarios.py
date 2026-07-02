"""Load and expand devcontainer test scenarios from YAML files."""

from __future__ import annotations

import fnmatch
import os
from pathlib import Path
from typing import TYPE_CHECKING, Any

import yaml

from proman.config import load as load_config
from proman.test.environments import is_macos

if TYPE_CHECKING:
    from collections.abc import Iterator

DEFAULT_MODES: tuple[str, ...] = ("devcontainer", "standalone")

# Applied when standalone.network: none or fast_net_fail: true
# (see merge_scenario_env_vars). lib/net.bash reads these when --retries/--delay
# are omitted. Success-path scenarios must not set them.
FAST_NET_FAIL_ENV_VARS: dict[str, str] = {
    "DEVFEATS_NET_FETCH_RETRIES": "1",
    "DEVFEATS_NET_FETCH_DELAY": "0",
}

# lib/logging.bash's recognized LOG_LEVEL / LOG_FILE_LEVEL values.
LOG_LEVELS: tuple[str, ...] = ("silent", "error", "warn", "info", "debug", "trace")

# Set by test-features.yaml from the ``runner.debug`` context (see
# docs/source/dev-guide/devops/ci.md) — truthy only during a GHA "re-run with
# debug logging". Signals CI wants xtrace without anyone passing --xtrace.
CI_DEBUG_ENV_VAR = "DEVFEATS_CI_DEBUG"

# Substrings in checks.yaml install-failure groups that mean the scenario exercises a
# blocked or unreachable network fetch (not merely a local validation error).
_NETWORK_FETCH_FAILURE_CHECK_NEEDLES: tuple[str, ...] = (
    "network is blocked",
    "github api unreachable",
    "unreachable uri",
    "devfeats-nonexistent-test-host.invalid",
)


def _install_failure_check_text(group: dict[str, Any]) -> str:
    parts: list[str] = []
    desc = group.get("description")
    if isinstance(desc, str):
        parts.append(desc)
    for item in group.get("checks") or []:
        if not isinstance(item, dict) or item.get("kind") != "install_failure":
            continue
        for key in ("title", "pattern"):
            val = item.get(key)
            if isinstance(val, str):
                parts.append(val)
    return "\n".join(parts).lower()


def scenario_expects_network_fetch_failure(
    checks: dict[str, Any],
    test_id: str,
) -> bool:
    """Return True when checks describe blocked/unreachable network fetch."""
    group = checks.get(test_id)
    if not isinstance(group, dict):
        return False
    text = _install_failure_check_text(group)
    return any(needle in text for needle in _NETWORK_FETCH_FAILURE_CHECK_NEEDLES)


def scenario_injects_fast_net_fail_env(scenario: dict[str, Any]) -> bool:
    """Return True when the runner should inject ``FAST_NET_FAIL_ENV_VARS``."""
    if scenario.get("fast_net_fail"):
        return True
    standalone = scenario.get("standalone")
    return isinstance(standalone, dict) and standalone.get("network") == "none"


def scenario_has_fast_net_fail_config(scenario: dict[str, Any]) -> bool:
    """Return True when the scenario opts into fast net-fetch failure."""
    if scenario_injects_fast_net_fail_env(scenario):
        return True
    env_vars = scenario.get("env_vars") or {}
    return isinstance(env_vars, dict) and "DEVFEATS_NET_FETCH_RETRIES" in env_vars


def network_fetch_failure_test_ids_missing_fast_config(
    checks: dict[str, Any],
    scenario: dict[str, Any],
) -> list[str]:
    """Return test IDs expecting network fetch failure without fast-net-fail config."""
    if not scenario.get("expect_install_failure"):
        return []
    if scenario_has_fast_net_fail_config(scenario):
        return []

    missing: list[str] = []
    for test_id in scenario.get("tests") or []:
        tid = str(test_id)
        if scenario_expects_network_fetch_failure(checks, tid):
            missing.append(tid)
    return missing


def merge_scenario_env_vars(scenario: dict[str, Any]) -> dict[str, str]:
    """Return scenario env_vars with fast net-fail defaults when configured."""
    env = {str(k): str(v) for k, v in (scenario.get("env_vars") or {}).items()}
    if scenario_injects_fast_net_fail_env(scenario):
        env = {**FAST_NET_FAIL_ENV_VARS, **env}
    return env


def resolve_log_overrides(
    *,
    log_level: str | None,
    log_file_level: str | None,
    xtrace: bool,
    environ: dict[str, str] | None = None,
) -> dict[str, str]:
    """Resolve LOG_LEVEL/LOG_FILE_LEVEL overrides for a whole test run.

    Precedence: explicit --log-level/--log-file-level/--xtrace flags, then the
    CI_DEBUG_ENV_VAR signal (xtrace), then empty (scenario/shared defaults apply).
    """
    overrides: dict[str, str] = {}
    if log_level:
        overrides["log_level"] = log_level
    if log_file_level:
        overrides["log_file_level"] = log_file_level
    if xtrace:
        overrides.setdefault("log_file_level", "trace")
    if overrides:
        return overrides

    environ = os.environ if environ is None else environ
    if environ.get(CI_DEBUG_ENV_VAR, "").strip().lower() in ("1", "true"):
        return {"log_file_level": "trace"}
    return {}


def apply_log_overrides(entries: list[dict], overrides: dict[str, str]) -> None:
    """Apply resolved log-level overrides in place across expanded runner entries."""
    if not overrides:
        return
    for entry in entries:
        options = {**entry["scenario"].get("options", {}), **overrides}
        entry["scenario"] = {**entry["scenario"], "options": options}


def load(path: Path | str) -> tuple[dict, dict]:
    """Load scenarios YAML and split off the defaults key."""
    with Path(path).open(encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        data = {}
    defaults = data.get("defaults", {})
    if not isinstance(defaults, dict):
        defaults = {}
    scenarios = {key: value for key, value in data.items() if key != "defaults"}
    return defaults, scenarios


def shared_defaults() -> dict:
    """Load test/features/defaults.shared.yaml when present."""
    path = load_config().absolute_path("path.test_features_shared_defaults")
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    return data if isinstance(data, dict) else {}


def merge_defaults(scenario: dict, defaults: dict) -> dict:
    """Merge top-level defaults into a scenario dict."""
    merged = dict(scenario)
    for key in ("options", "args", "env_vars"):
        if key in defaults:
            base = dict(defaults[key])
            base.update(scenario.get(key, {}))
            merged[key] = base
    return merged


def merge_all_defaults(
    scenario: dict,
    feature_defaults: dict,
    shared: dict | None = None,
) -> dict:
    """Merge shared, feature-level, then scenario-level defaults/options."""
    merged: dict = {}
    for layer in [shared or {}, feature_defaults or {}, scenario]:
        for key, value in layer.items():
            if (
                key in merged
                and isinstance(merged[key], dict)
                and isinstance(value, dict)
            ):
                merged[key] = {**merged[key], **value}
            else:
                merged[key] = value
    return merged


def expand_envs(
    name: str,
    scenario: dict,
) -> list[tuple[str, str, dict]]:
    """Expand a scenario into one entry per (environment, test file)."""
    envs: list[str] = scenario.get("envs", [])
    tests: list[str] = scenario.get("tests", [])
    multi_test = len(tests) > 1

    entries = []
    test_iter: list = tests or [None]
    for env_name in envs:
        for test_file in test_iter:
            parts = [name, env_name]
            if multi_test:
                parts.append(test_file)
            sc = dict(scenario)
            if test_file is not None:
                sc["tests"] = [test_file]
            entries.append((".".join(parts), env_name, sc))

    return entries


def iter_merged_scenarios(
    defaults: dict,
    scenarios: dict,
    shared: dict | None = None,
) -> Iterator[tuple[str, dict]]:
    """Yield ``(scenario_name, merged_scenario)`` with all defaults applied."""
    layer = shared if shared is not None else shared_defaults()
    for name, scenario in scenarios.items():
        if not isinstance(scenario, dict):
            continue
        yield name, merge_all_defaults(scenario, defaults, layer)


def expand_feature_entries(
    defaults: dict,
    scenarios: dict,
    envs: dict[str, Any],
    *,
    shared: dict | None = None,
) -> list[dict]:
    """Expand scenarios into runner entries (same shape as run.py matrix entries)."""
    entries: list[dict] = []
    for name, merged_sc in iter_merged_scenarios(defaults, scenarios, shared):
        for key, env_name, sc in expand_envs(name, merged_sc):
            entries.append(
                {
                    "key": key,
                    "env_name": env_name,
                    "env_is_macos": is_macos(env_name, envs),
                    "scenario": sc,
                },
            )
    return entries


def expand_test_files(
    tests_spec: dict | list | None,
    base_dir: Path | str,
) -> list[str]:
    """Expand a tests spec into a list of absolute file paths."""
    base = Path(base_dir)

    if tests_spec is None:
        includes = ["*.bats", "integration/*.bats"]
        excludes = []
    elif isinstance(tests_spec, dict):
        includes = tests_spec.get("includes", ["*.bats"])
        excludes = tests_spec.get("excludes", [])
    else:
        return []

    matched: set[Path] = set()
    for pattern in includes:
        matched.update(base.glob(pattern))

    result: list[str] = []
    for p in sorted(matched):
        rel = str(p.relative_to(base))
        excluded = any(fnmatch.fnmatch(rel, exc) for exc in excludes)
        if not excluded:
            result.append(str(p))

    return result
