"""Validated configuration model for the library-test platform matrix."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import yaml

from .environments import resolve_attributes

_PLATFORM_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
PROFILES = ("ordinary", "bootstrap")


class LibScenarioError(ValueError):
    """Invalid ``test/lib/scenarios.yaml`` data."""


def load_and_validate(
    path: Path | str,
    environments: object,
) -> dict[str, dict[str, dict[str, Any]]]:
    """Load raw YAML and apply the shared runtime/CI validation contract."""
    source = Path(path)
    try:
        platforms = yaml.safe_load(source.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        message = f"Cannot load library test scenarios from {source}: {exc}"
        raise LibScenarioError(message) from exc
    return validate(platforms, environments)


def validate(
    platforms: object,
    environments: object,
) -> dict[str, dict[str, dict[str, Any]]]:
    """Validate and return the ordered platform/profile mapping.

    Runtime orchestration and CI detection both call this function so their
    accepted configuration cannot drift apart.
    """
    if not isinstance(platforms, dict):
        message = "Library test platforms must be a mapping."
        raise LibScenarioError(message)
    if not platforms:
        message = "Library test platforms must not be empty."
        raise LibScenarioError(message)
    if not isinstance(environments, dict):
        message = "Test environments must be a mapping."
        raise LibScenarioError(message)

    for platform, profiles in platforms.items():
        if not isinstance(platform, str) or not _PLATFORM_NAME_RE.fullmatch(platform):
            message = f"Library test platform name {platform!r} is invalid."
            raise LibScenarioError(message)
        if not isinstance(profiles, dict):
            message = f"Library test platform {platform!r} must be a mapping."
            raise LibScenarioError(message)
        actual_profiles = set(profiles)
        expected_profiles = set(PROFILES)
        if actual_profiles != expected_profiles:
            missing = expected_profiles - actual_profiles
            extra = actual_profiles - expected_profiles
            details = []
            if missing:
                details.append(
                    "missing profiles: "
                    + ", ".join(repr(key) for key in sorted(missing, key=str))
                )
            if extra:
                details.append(
                    "unknown profiles: "
                    + ", ".join(repr(key) for key in sorted(extra, key=str))
                )
            message = (
                f"Library test platform {platform!r} must define exactly ordinary "
                f"and bootstrap ({'; '.join(details)})."
            )
            raise LibScenarioError(message)

        for profile_name in PROFILES:
            profile = profiles[profile_name]
            prefix = f"Library test platform {platform!r} profile {profile_name!r}"
            if not isinstance(profile, dict):
                message = f"{prefix} must be a mapping."
                raise LibScenarioError(message)
            unknown_keys = set(profile) - {"env", "env_vars"}
            if unknown_keys:
                keys = ", ".join(repr(key) for key in sorted(unknown_keys, key=str))
                message = f"{prefix} has unknown keys: {keys}."
                raise LibScenarioError(message)
            env_name = profile.get("env")
            if not isinstance(env_name, str) or not env_name:
                message = f"{prefix} must define a non-empty string 'env'."
                raise LibScenarioError(message)
            if env_name not in environments:
                message = f"{prefix} references unknown environment {env_name!r}."
                raise LibScenarioError(message)
            expected_role = "prepared" if profile_name == "ordinary" else "bare"
            env_spec = environments[env_name]
            if not isinstance(env_spec, dict):
                message = f"Environment {env_name!r} must be a mapping."
                raise LibScenarioError(message)
            actual_role = env_spec.get("lib_test_profile")
            if actual_role != expected_role:
                message = (
                    f"{prefix} requires an environment with lib_test_profile "
                    f"{expected_role!r}; {env_name!r} declares {actual_role!r}."
                )
                raise LibScenarioError(message)
            env_vars = profile.get("env_vars")
            if not isinstance(env_vars, dict) or not all(
                isinstance(key, str) and isinstance(value, str)
                for key, value in env_vars.items()
            ):
                message = f"{prefix} env_vars must map strings to strings."
                raise LibScenarioError(message)
            expected_env_vars = (
                {
                    "DEVFEATS_TEST_TOOL_CACHE": "required",
                    "DEVFEATS_TEST_TOOL_SOURCE_DIR": (
                        "/opt/devfeats/lib-test-tools/bin"
                    ),
                }
                if profile_name == "ordinary"
                else {"DEVFEATS_TEST_TOOL_CACHE": "disabled"}
            )
            if env_vars != expected_env_vars:
                message = f"{prefix} env_vars must be exactly {expected_env_vars!r}."
                raise LibScenarioError(message)
        if profiles["ordinary"]["env"] == profiles["bootstrap"]["env"]:
            message = (
                f"Library test platform {platform!r} ordinary and bootstrap "
                "profiles must reference distinct environments."
            )
            raise LibScenarioError(message)
        ordinary_env = profiles["ordinary"]["env"]
        bootstrap_env = profiles["bootstrap"]["env"]
        cursor: str | None = ordinary_env
        seen: set[str] = set()
        while cursor is not None and cursor not in seen and cursor != bootstrap_env:
            seen.add(cursor)
            env_spec = environments.get(cursor)
            if not isinstance(env_spec, dict):
                break
            parent = env_spec.get("from")
            cursor = parent if isinstance(parent, str) and parent else None
        if cursor != bootstrap_env:
            message = (
                f"Library test platform {platform!r} ordinary environment "
                f"{ordinary_env!r} must derive from its bootstrap environment "
                f"{bootstrap_env!r}."
            )
            raise LibScenarioError(message)
        try:
            ordinary_attributes = resolve_attributes(ordinary_env, environments)
            bootstrap_attributes = resolve_attributes(bootstrap_env, environments)
        except (KeyError, RecursionError, TypeError, ValueError) as exc:
            message = (
                f"Library test platform {platform!r} has an invalid environment "
                f"inheritance chain: {exc}"
            )
            raise LibScenarioError(message) from exc
        if ordinary_attributes != bootstrap_attributes:
            message = (
                f"Library test platform {platform!r} ordinary and bootstrap "
                "profiles must resolve to identical platform attributes."
            )
            raise LibScenarioError(message)
    return platforms
