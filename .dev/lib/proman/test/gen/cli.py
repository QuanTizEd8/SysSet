"""CLI: `proman-test-gen-preview <feature>` — preview generated tests.

Prints the scenarios/checks the test-generation pipeline would produce for
one feature, without writing anything to disk. Used to review a rule's effect
before enabling it in `generation.yaml`'s rollout allowlist, and during
migration to compare generated output against a feature's current
hand-written files.
"""

from __future__ import annotations

import argparse
import sys

import yaml

from proman.config import load as load_config
from proman.metadata import MetadataLoader
from proman.test import gen
from proman.test.environments import load as load_environments
from proman.test.gen import config as gen_config


def main() -> None:
    """Print generated scenarios/checks for one feature."""
    parser = argparse.ArgumentParser(
        description="Preview generated test scenarios/checks for one feature.",
    )
    parser.add_argument("feature", help="Feature id (e.g. install-jq).")
    args = parser.parse_args()

    cfg = gen_config.load()
    envs = load_environments(load_config().absolute_path("path.test_environments"))
    metadata = MetadataLoader().load(args.feature)[args.feature]
    result = gen.generate_feature_tests(args.feature, metadata, cfg, envs)

    if not result.scenarios and not result.checks:
        print(
            f"(nothing generated for {args.feature!r} — check generation.yaml's "
            "rollout allowlist/denylist and family enablement)",
            file=sys.stderr,
        )
        return

    print("# scenarios")
    print(yaml.dump(result.scenarios, sort_keys=False, default_flow_style=False))
    print("# checks")
    print(yaml.dump(result.checks, sort_keys=False, default_flow_style=False))


if __name__ == "__main__":
    main()
