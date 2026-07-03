"""Canonical scenario/check names.

Codifies the "Naming Conventions" table in
docs/source/dev-guide/tests/features.md so every rule produces the same
shape of name a human author would, instead of each rule inventing its own.
"""

from __future__ import annotations


def method_scenario_name(method: str) -> str:
    """`package` -> `package_default`, `npm-bundled` -> `npm_bundled_default`, etc."""
    return f"{method.replace('-', '_')}_default"


def pinned_scenario_name(index: int, total: int) -> str:
    """Build the pinned-version scenario name (1-based `index`).

    `version_pinned` for a single declared pin, else `version_pinned_<n>`.
    """
    return "version_pinned" if total == 1 else f"version_pinned_{index + 1}"


def legacy_scenario_name(index: int, total: int) -> str:
    """Build the legacy-version scenario name (1-based `index`).

    `version_legacy` for a single declared legacy version, else
    `version_legacy_<n>`.
    """
    return "version_legacy" if total == 1 else f"version_legacy_{index + 1}"


def invalid_option_scenario_name(option: str) -> str:
    """`invalid_method`, `invalid_if_exists`, `invalid_<option>` generally."""
    return f"invalid_{option}"


def completions_scenario_name(shell: str) -> str:
    """`completions_bash`, `completions_zsh`, etc."""
    return f"completions_{shell}"
