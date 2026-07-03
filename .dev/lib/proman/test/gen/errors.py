"""Exceptions raised by the test-generation pipeline (proman.test.gen)."""

from __future__ import annotations


class GeneratorInternalError(Exception):
    """A generator bug, not a data problem.

    E.g. two rules produced the same scenario/check-group name for one
    feature. Rules are written to be feature-agnostic and mutually
    independent, so this should never happen; it signals a defect in a rule
    or the engine, not bad input data.
    """


class GenerationConfigError(ValueError):
    """Bad `generation.yaml` content, or an unresolvable per-feature override.

    E.g. a `generation:` block referencing an unknown environment.
    """
