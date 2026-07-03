"""CLI entry point for validating feature test YAML definitions."""

from __future__ import annotations

import argparse
import sys

import yaml
from jsonschema.exceptions import ValidationError

from proman.config import load as load_config
from proman.schema_bundle import get_environments_validator
from proman.test.loader import FeatureTestError, FeatureTestLoader


def _validate_one(loader: FeatureTestLoader, feature_id: str) -> bool:
    """Validate one feature; print result; return True on success."""
    try:
        loader.load(feature_id)
    except (FeatureTestError, FileNotFoundError) as exc:
        print(f"⛔ {exc}", file=sys.stderr)
        return False
    print(f"✔  test/features/{feature_id}")
    return True


def _validate_environments() -> bool:
    """Validate test/environments.yaml against environments.schema.json."""
    path = load_config().absolute_path("path.test_environments")
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    try:
        get_environments_validator().validate(data)
    except ValidationError as exc:
        print(f"⛔ {path}: {exc.message}", file=sys.stderr)
        return False
    print(f"✔  {path}")
    return True


def main() -> None:
    """Validate checks.yaml and scenarios.yaml for one or all feature tests."""
    parser = argparse.ArgumentParser(
        description="Validate feature test checks.yaml and scenarios.yaml files.",
    )
    parser.add_argument(
        "feature",
        nargs="?",
        help="Feature id (e.g. install-jq). Omit to validate all features.",
    )
    args = parser.parse_args()

    results = [_validate_environments()] if not args.feature else []
    loader = FeatureTestLoader()
    feature_ids = [args.feature] if args.feature else loader.feature_ids()
    results += [_validate_one(loader, fid) for fid in feature_ids]
    if not all(results):
        sys.exit(1)


if __name__ == "__main__":
    main()
