"""Scenario-family rule modules.

Every module in this package registers itself via `proman.test.gen.registry.register`
as a side effect of being imported — this `__init__.py` is the single place that
imports all of them, so `engine.py` (which imports this package) sees every
registered rule without listing any of them by name.

No rule modules exist yet: the generation pipeline currently produces empty
output for every feature regardless of `generation.yaml`'s rollout settings.
Rules land here one scenario family at a time, per the migration plan.
"""

from __future__ import annotations
