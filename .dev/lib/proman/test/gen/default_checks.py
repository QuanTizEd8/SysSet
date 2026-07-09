"""The comprehensive install-outcome check bundle shared by the install rules.

Given a feature's facts and the computed `ExpectedOutcome`, emits assertions for
*every* observable part of the outcome — the exact binary location(s), PATH
resolution, version, functional smoke, recorded install-method, symlink
presence/absence, and the PATH-export/discovery block's presence-with-exact-
content or absence — positive **and** negative. Used by `existence_default` and
`method_matrix`'s reused method variants so a generated scenario proves the full
install state, not just "a binary exists".
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import blocks, checks_builtin
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
    """Build the full install-outcome check bundle.

    `method_pinned=True` (explicit `method:` scenario) asserts the recorded
    install-method by value; `False` (`method=auto`) asserts only that a method
    was recorded, since a feature `__resolve_method` hook can override the
    generation-time prediction. The exact install location, symlink, and export
    block are asserted regardless — they follow from the resolved outcome, and a
    mismatch is a real signal (fix the resolver, or a genuine feature bug).
    """
    if facts.is_git_clone_only:
        return _git_clone_checks(facts)

    if outcome is not None and not outcome.on_path and outcome.install_path:
        items = _off_path_items(facts, cfg, outcome)
    elif outcome is not None and outcome.install_path:
        items = _on_path_prefix_items(facts, cfg, outcome)
    else:
        items = _generic_path_items(facts, cfg, outcome)

    items.extend(_method_items(outcome, method_pinned=method_pinned))
    items.extend(_symlink_items(outcome))
    items.extend(_export_items(facts, outcome))
    items.extend(_activation_items(facts, outcome))
    return items


def _version_item(
    facts: FeatureFacts, outcome: ExpectedOutcome | None, bin_value: str
) -> CheckItem:
    """Exact version cross-validation when the scenario resolves one, else format."""
    if outcome is not None and outcome.version:
        return checks_builtin.version_exact_check(
            bin_value, facts.version_flag, outcome.version
        )
    return checks_builtin.version_format_check(bin_value, facts.version_flag)


def _on_path_prefix_items(
    facts: FeatureFacts, cfg: GenerationConfig, outcome: ExpectedOutcome
) -> list[CheckItem]:
    """Prefix install reachable on PATH: assert the EXACT location of every bin."""
    install_dir = outcome.install_path.rsplit("/", 1)[0]
    items: list[CheckItem] = []
    for b in facts.bins or [facts.primary_bin]:
        items.extend(checks_builtin.install_location_checks(b, f"{install_dir}/{b}"))
    items.append(_version_item(facts, outcome, facts.primary_bin))
    items.extend(_functional_items(facts, cfg, facts.primary_bin))
    return items


def _generic_path_items(
    facts: FeatureFacts, cfg: GenerationConfig, outcome: ExpectedOutcome | None
) -> list[CheckItem]:
    """PM-managed / self-managed install: location not separately predictable."""
    primary = facts.primary_bin
    items: list[CheckItem] = [
        CheckItem(title=f"{b} is on PATH", cmd=f"command -v {b}")
        for b in (facts.bins or [primary])
    ]
    items.append(
        CheckItem(
            title=f"{primary} binary is executable",
            cmd=f"bash -c 'test -x \"$(command -v {primary})\"'",
        ),
    )
    items.append(_version_item(facts, outcome, primary))
    items.extend(_functional_items(facts, cfg, primary))
    return items


def _off_path_items(
    facts: FeatureFacts,
    cfg: GenerationConfig,
    outcome: ExpectedOutcome,
) -> list[CheckItem]:
    """Check an off-default-PATH install by absolute path plus a login probe.

    For a binary installed to a skip-symlink+skip-export prefix, existence,
    version, and functional checks all run against the absolute install path.
    Adds a login-shell reachability probe (`bash -lc 'command -v ...'`): the tool
    is put on PATH only in a login/interactive shell, by whichever mechanism the
    feature uses (homebrew's discovery snippet, a feature's activation block), so
    this one probe covers the reachability while `_export_items` separately
    asserts the exact discovery-block content.
    """
    primary = facts.primary_bin
    install_dir = outcome.install_path.rsplit("/", 1)[0]
    items: list[CheckItem] = []
    for b in facts.bins or [primary]:
        path = f"{install_dir}/{b}"
        items.append(
            CheckItem(title=f"{b} is installed at {path}", cmd=f"test -x {path}"),
        )
    primary_path = f"{install_dir}/{primary}"
    items.append(_version_item(facts, outcome, primary_path))
    items.extend(_functional_items(facts, cfg, primary_path))
    items.append(
        CheckItem(
            title=f"{primary} is reachable in a login shell",
            cmd=f"bash -lc 'command -v {primary}'",
        ),
    )
    return items


def _method_items(
    outcome: ExpectedOutcome | None,
    *,
    method_pinned: bool,
) -> list[CheckItem]:
    """Assert the recorded install-method (by value when pinned, else existence)."""
    if outcome is None or outcome.method is None:
        return []
    if not method_pinned:
        return [checks_builtin.installed_method_recorded_check(outcome.share_dir_var)]
    return [
        checks_builtin.installed_method_check(outcome.method, outcome.share_dir_var)
    ]


def _symlink_items(outcome: ExpectedOutcome | None) -> list[CheckItem]:
    """Positive/negative symlink assertions from the outcome."""
    if outcome is None:
        return []
    items: list[CheckItem] = []
    if outcome.symlink is not None:
        items.extend(
            checks_builtin.symlink_present_checks(
                outcome.symlink.target, outcome.symlink.link_path
            ),
        )
    if outcome.no_symlink_at is not None:
        items.append(checks_builtin.symlink_absent_check(outcome.no_symlink_at))
    return items


def _export_items(
    facts: FeatureFacts, outcome: ExpectedOutcome | None
) -> list[CheckItem]:
    """PATH-export/discovery block: exact content when written, else absent."""
    if outcome is None:
        return []
    if outcome.export_block is not None:
        eb = outcome.export_block
        return [
            checks_builtin.block_equals_check(
                eb.file_expr,
                eb.marker,
                list(eb.content_lines),
                title="PATH-export block content is exact",
            ),
        ]
    if outcome.assert_no_export_block:
        return [
            checks_builtin.block_absent_check(
                blocks.PROFILE_D_EXPR,
                blocks.export_marker(facts),
                title="no PATH-export block written",
            ),
        ]
    return []


def _activation_items(
    facts: FeatureFacts, outcome: ExpectedOutcome | None
) -> list[CheckItem]:
    """Assert the shell-activation block was written (structural: marker present).

    A feature with `_options.prefix.activation.shells` writes a `# >>> prefix
    activation (<id>) >>>` block (content from its `__prefix_activation_snippet`
    hook — feature-code-generated, e.g. `eval "$(direnv hook bash)"` — so not
    byte-predictable from metadata). `prefix_activations` defaults to every
    declared shell, so a default install writes it. Root-scope only: a non-root
    install writes to per-user rc files, probed structurally via the login shell.
    """
    if not facts.activation_shells or outcome is None:
        return []
    if outcome.share_dir_var != "_FEAT_SHARE_DIR_ROOT":
        return []
    return [checks_builtin.activation_block_present_check(facts.feature_id)]


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
