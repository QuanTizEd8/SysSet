"""Test-generation pipeline: derives scenarios/checks from a feature's metadata.yaml.

Public entry point: `engine.generate_feature_tests()`. Everything under this
package is pure and in-memory — nothing here ever writes to
`test/features/<id>/`; generated content is merged with hand-written
scenarios.yaml/checks.yaml at load time by `proman.test.effective`.
"""

from __future__ import annotations

from proman.test.gen.engine import generate_feature_tests
from proman.test.gen.types import CheckGroup, CheckItem, GeneratedScenario

__all__ = [
    "CheckGroup",
    "CheckItem",
    "GeneratedScenario",
    "generate_feature_tests",
]
