"""Load and validate feature test definitions.

Covers checks.yaml and scenarios.yaml, merged with any generated content —
see proman.test.effective.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING

from jsonschema.exceptions import ValidationError

from proman.config import load as load_config
from proman.schema_bundle import get_checks_validator, get_scenarios_validator
from proman.test.effective import FeatureTestError, load_effective
from proman.test.environments import load as load_environments
from proman.test.scenarios import (
    DEFAULT_MODES,
    expand_feature_entries,
    iter_merged_scenarios,
    network_fetch_failure_test_ids_missing_fast_config,
    shared_defaults,
)

if TYPE_CHECKING:
    from pathlib import Path

    from proman.test.effective import Provenance

__all__ = ["FeatureTestError", "FeatureTestLoader", "FeatureTests"]


@dataclass(frozen=True)
class FeatureTests:
    """Validated, effective (hand-written + generated) tests for one feature."""

    feature_id: str
    checks: dict
    defaults: dict
    scenarios: dict
    checks_path: Path
    scenarios_path: Path
    provenance: dict[str, Provenance] = field(default_factory=dict)

    def expand_entries(self, envs: dict) -> list[dict]:
        """Expand validated scenarios into runner matrix entries."""
        return expand_feature_entries(self.defaults, self.scenarios, envs)


class FeatureTestLoader:
    """Authoritative loader for feature test YAML under test/features/."""

    def __init__(self) -> None:
        self._config = load_config()
        self._test_features = self._config.absolute_path("path.test_features")
        self._checks_name = str(self._config["filename.feature_checks"])
        self._scenarios_name = str(self._config["filename.feature_scenarios"])
        self._environments_path = self._config.absolute_path("path.test_environments")
        self._checks_validator = get_checks_validator()
        self._scenarios_validator = get_scenarios_validator()
        self._known_envs = self._load_known_envs()

    def load(self, feature_id: str) -> FeatureTests:
        """Load, validate, and return checks + scenarios for one feature."""
        feat_dir = self._test_features / feature_id
        if not feat_dir.is_dir():
            msg = f"Feature test directory not found: {feat_dir}"
            raise FileNotFoundError(msg)

        checks_path = feat_dir / self._checks_name
        scenarios_path = feat_dir / self._scenarios_name

        if not checks_path.is_file():
            msg = (
                f"Missing {self._checks_name} for feature '{feature_id}': {checks_path}"
            )
            raise FileNotFoundError(msg)
        if not scenarios_path.is_file():
            msg = (
                f"Missing {self._scenarios_name} for feature '{feature_id}':"
                f" {scenarios_path}"
            )
            raise FileNotFoundError(msg)

        effective = load_effective(feature_id)

        self._validate_checks_schema(effective.checks, checks_path)
        scenarios_doc = dict(effective.scenarios)
        if effective.defaults:
            scenarios_doc["defaults"] = effective.defaults
        self._validate_scenarios_schema(scenarios_doc, scenarios_path)

        ft = FeatureTests(
            feature_id=feature_id,
            checks=effective.checks,
            defaults=effective.defaults,
            scenarios=effective.scenarios,
            checks_path=checks_path,
            scenarios_path=scenarios_path,
            provenance=effective.provenance,
        )
        self._validate_cross_file(ft)
        return ft

    def load_all(self) -> list[FeatureTests]:
        """Load and validate every feature test directory that has checks.yaml."""
        return [self.load(feature_id) for feature_id in self.feature_ids()]

    def feature_ids(self) -> list[str]:
        """Sorted list of feature IDs that have a checks.yaml."""
        return sorted(p.name for p in self._feature_dirs())

    def _feature_dirs(self) -> list[Path]:
        return [
            p
            for p in self._test_features.iterdir()
            if p.is_dir() and (p / self._checks_name).is_file()
        ]

    def _load_known_envs(self) -> set[str]:
        if not self._environments_path.is_file():
            return set()
        data = load_environments(self._environments_path)
        return {key for key in data if key != "defaults" and isinstance(key, str)}

    def _validate_checks_schema(self, checks: dict, path: Path) -> None:
        try:
            self._checks_validator.validate(checks)
        except ValidationError as exc:
            msg = f"{path}: checks schema validation failed: {exc.message}"
            raise FeatureTestError(msg) from exc

    def _validate_scenarios_schema(self, scenarios_doc: dict, path: Path) -> None:
        try:
            self._scenarios_validator.validate(scenarios_doc)
        except ValidationError as exc:
            msg = f"{path}: scenarios schema validation failed: {exc.message}"
            raise FeatureTestError(msg) from exc

    def _validate_cross_file(self, ft: FeatureTests) -> None:
        if not ft.scenarios:
            msg = (
                f"{ft.scenarios_path}: no scenarios defined"
                " (file contains only 'defaults')"
            )
            raise FeatureTestError(msg)
        shared = shared_defaults()
        for scenario_name, merged in iter_merged_scenarios(
            ft.defaults,
            ft.scenarios,
            shared,
        ):
            self._validate_merged_scenario(
                feature_id=ft.feature_id,
                scenario_name=scenario_name,
                merged=merged,
                checks=ft.checks,
                scenarios_path=ft.scenarios_path,
            )

    def _validate_merged_scenario(
        self,
        *,
        feature_id: str,
        scenario_name: str,
        merged: dict,
        checks: dict,
        scenarios_path: Path,
    ) -> None:
        envs = merged.get("envs") or []
        if not envs:
            msg = (
                f"{scenarios_path}: scenario '{scenario_name}' has no envs after"
                " merging defaults (each scenario must define or inherit envs)"
            )
            raise FeatureTestError(msg)

        if self._known_envs:
            unknown = sorted(set(envs) - self._known_envs)
            if unknown:
                msg = (
                    f"{scenarios_path}: scenario '{scenario_name}' references unknown"
                    f" environment(s): {', '.join(unknown)}"
                )
                raise FeatureTestError(msg)

        test_ids = merged.get("tests") or []
        for raw_test_id in test_ids:
            test_id = str(raw_test_id)
            if test_id not in checks:
                msg = (
                    f"{scenarios_path}: scenario '{scenario_name}' references test"
                    f" '{raw_test_id}' but {feature_id}/checks.yaml has no group"
                    f" '{test_id}'"
                )
                raise FeatureTestError(msg)

        missing_fast = network_fetch_failure_test_ids_missing_fast_config(
            checks,
            merged,
        )
        if missing_fast:
            test_id = missing_fast[0]
            msg = (
                f"{scenarios_path}: scenario '{scenario_name}' test"
                f" '{test_id}' expects a network fetch failure; set"
                " standalone.network: none, fast_net_fail: true, or"
                " env_vars.DEVFEATS_NET_FETCH_RETRIES"
            )
            raise FeatureTestError(msg)

        if not merged.get("expect_install_failure"):
            return

        modes = merged.get("modes", list(DEFAULT_MODES))
        if "devcontainer" not in modes:
            return

        for raw_test_id in test_ids:
            test_id = str(raw_test_id)
            group = checks[test_id]
            for idx, item in enumerate(group.get("checks", [])):
                kind = item.get("kind", "check")
                if kind != "install_failure":
                    msg = (
                        f"{scenarios_path}: scenario '{scenario_name}' sets"
                        " expect_install_failure with devcontainer in modes, but"
                        f" checks.yaml group '{test_id}' item {idx + 1} has"
                        f" kind={kind!r}. Devcontainer expected-failure runs never"
                        " start the test container, so only install_failure checks"
                        " are executed. Restrict modes to standalone and/or macos,"
                        " or remove non-install_failure checks."
                    )
                    raise FeatureTestError(msg)
