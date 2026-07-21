"""CLI entry point for proman-test-lib-matrix."""

from __future__ import annotations

import argparse
import re
import sys

from proman.test.github_auth import ensure_github_token
from proman.test.lib_matrix import run


def main() -> None:
    """Run lib/ tests across container environments."""
    parser = argparse.ArgumentParser(
        description="Run lib/ tests across container environments.",
    )
    parser.add_argument(
        "--platform",
        metavar="NAME",
        default=None,
        help="Run exactly this logical platform.",
    )
    parser.add_argument(
        "--workload",
        choices=("ordinary", "bootstrap", "complete"),
        default="ordinary",
        help="Select ordinary, bootstrap, or both profiles (default: ordinary).",
    )
    parser.add_argument(
        "--ordinary-tier",
        choices=("lean", "integration", "all"),
        default="lean",
        help="Select the ordinary profile tier (default: lean).",
    )
    parser.add_argument(
        "--matrix-jobs",
        type=_positive_int,
        default=3,
        metavar="N",
        help="Maximum concurrent platform workers (default: 3).",
    )
    parser.add_argument(
        "runner_args",
        nargs=argparse.REMAINDER,
        help="Arguments after -- are forwarded to run-unit.sh.",
    )
    raw_args = sys.argv[1:]
    args = parser.parse_args(raw_args)
    if args.runner_args and "--" not in raw_args:
        parser.error("runner arguments must follow a literal --")
    runner_args = args.runner_args
    if runner_args[:1] == ["--"]:
        runner_args = runner_args[1:]
    ensure_github_token()
    sys.exit(
        run(
            args.platform,
            args.workload,
            args.ordinary_tier,
            args.matrix_jobs,
            runner_args,
        ),
    )


def _positive_int(value: str) -> int:
    """Parse a positive decimal command-line integer."""
    if not re.fullmatch(r"[0-9]{1,9}", value):
        message = "expected a positive integer"
        raise argparse.ArgumentTypeError(message)
    parsed = int(value, 10)
    if parsed < 1:
        message = "expected a positive integer"
        raise argparse.ArgumentTypeError(message)
    return parsed
