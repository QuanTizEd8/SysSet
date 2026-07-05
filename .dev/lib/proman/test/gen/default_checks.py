"""The "does the tool work" check bundle shared by two rules.

Used by `existence_default` and `method_matrix`'s method variants that reuse
it verbatim (source/npm/npm-bundled/cargo/script/git-clone) — a composed
builder, not a rule itself, so rules that need it import this module rather
than each other (rules stay mutually independent per the plug-in design in
`registry.py`).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import checks_builtin
from proman.test.gen.errors import GenerationConfigError
from proman.test.gen.types import CheckItem

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts
    from proman.test.gen.outcome import ExpectedOutcome


def build(
    facts: FeatureFacts,
    cfg: GenerationConfig,
    outcome: ExpectedOutcome | None = None,
    *,
    method_pinned: bool = True,
) -> list[CheckItem]:
    """Build the existence/version/functional (or git-clone) check bundle.

    When `outcome` is given, the bundle is enriched with expected-outcome
    assertions. `method_pinned` distinguishes the two ways the outcome's method
    was obtained: `True` (the scenario pinned an explicit `method:`) means the
    recorded installed-method and install location are guaranteed, so both are
    asserted by value. `False` (the scenario ran `method=auto`) means the
    method is a generation-time *prediction* that a feature `__resolve_method`
    hook can override — so only "a method was recorded" is asserted, not which.
    Called without `outcome`, behaves as before (no outcome assertions).
    """
    if facts.is_git_clone_only:
        return _git_clone_checks(facts)

    bins = facts.bins or [facts.primary_bin]
    items: list[CheckItem] = [
        CheckItem(title=f"{b} is on PATH", cmd=f"command -v {b}") for b in bins
    ]
    primary = facts.primary_bin
    items.append(
        CheckItem(
            title=f"{primary} binary is executable",
            cmd=f"bash -c 'test -x \"$(command -v {primary})\"'",
        ),
    )
    items.append(checks_builtin.version_format_check(primary, facts.version_flag))
    items.extend(_functional_items(facts, cfg, primary))
    items.extend(_outcome_items(facts, outcome, method_pinned=method_pinned))
    return items


def _outcome_items(
    facts: FeatureFacts,
    outcome: ExpectedOutcome | None,
    *,
    method_pinned: bool,
) -> list[CheckItem]:
    """Expected-outcome assertions layered onto the base bundle."""
    if outcome is None or outcome.method is None:
        return []
    if not method_pinned:
        # Auto-resolved: the method (and hence install location) is a prediction
        # a feature hook can override, so assert only that recording happened.
        return [checks_builtin.installed_method_recorded_check(outcome.share_dir_var)]
    items = [
        checks_builtin.installed_method_check(outcome.method, outcome.share_dir_var),
    ]
    if outcome.install_path is not None:
        items.append(
            CheckItem(
                title=f"{facts.primary_bin} binary is at {outcome.install_path}",
                cmd=f"test -f {outcome.install_path}",
            ),
        )
    return items


def _functional_items(
    facts: FeatureFacts,
    cfg: GenerationConfig,
    bin_value: str,
) -> list[CheckItem]:
    functional = facts.functional
    if functional is not None:
        cmd_template, description = functional
        return [checks_builtin.functional_check(cmd_template, description, bin_value)]
    if cfg.functional_smoke_required and (facts.methods or facts.version):
        msg = (
            f"{facts.feature_id}: _options.method/_options.version is declared but "
            "_options.verify.functional is missing. Declare it (required by "
            "generation.yaml's assertions.functional_smoke_required), or disable "
            "that assertion globally if this feature genuinely has no meaningful "
            "functional smoke test."
        )
        raise GenerationConfigError(msg)
    return []


def _git_clone_checks(facts: FeatureFacts) -> list[CheckItem]:
    prefix = facts.default_prefix_root
    items: list[CheckItem] = [
        CheckItem(title="install directory exists", cmd=f'test -d "{prefix}"'),
        CheckItem(
            title="install directory is a git repository",
            cmd=f'test -d "{prefix}/.git"',
        ),
    ]
    for key, value in facts.git_clone_config().items():
        items.append(
            CheckItem(
                title=f"{key} git config set",
                cmd=f'bash -c \'test "$(git -C "{prefix}" config {key})" = "{value}"\'',
            ),
        )
    return items
