"""Scenario-family rule modules.

Every module in this package registers itself via `proman.test.gen.registry.register`
as a side effect of being imported — this `__init__.py` is the single place that
imports all of them, so `engine.py` (which imports this package) sees every
registered rule without listing any of them by name.
"""

from __future__ import annotations

from proman.test.gen.rules import (  # noqa: F401
    completions,
    configure_users,
    existence_default,
    if_exists,
    invalid_enum,
    log_file,
    method_matrix,
    prefix_symlink,
    version_pinning,
)
