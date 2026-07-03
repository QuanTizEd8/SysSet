"""Custom-prefix + symlink-discovery scenario family.

Covers `custom_prefix_symlink`/`custom_prefix_no_symlink`: install at a
non-default prefix, verify symlink discovery behaves as configured. Trigger:
`_options.prefix.bins` non-empty and symlinks aren't globally skipped.

A non-root variant (`custom_prefix_symlink_nonroot`) was tried and reverted:
the test runner always installs as root regardless of the chosen
environment's user (confirmed by a real Docker run — the generated
"symlink at ~/.local/bin" checks failed because the install never actually
ran as the non-root user). install-git's own non-root scenario needs
`standalone.skip_install: true` plus a hand-written `pre:` that manually
re-invokes install.sh via `su <user>` — there's no generic, feature-agnostic
form of that yet, and devcontainer mode has the same problem (image builds
always run as root regardless of `remoteUser`). Left as follow-up work
rather than shipping a confirmed-broken generated scenario.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import checks_builtin
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, CheckItem, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "prefix_symlink"


@register
class PrefixSymlinkRule:
    """Generates the custom-prefix + symlink-discovery scenario family."""

    family = _FAMILY
    check_generation = "full"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:  # noqa: ARG002
        """Whether this feature has PATH-exposed bins with symlinks not skipped."""
        return bool(facts.bins) and not facts.symlink_skipped

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,  # noqa: ARG002
    ) -> list[GeneratedScenario]:
        """Generate the root symlink and no-symlink scenarios."""
        return [
            self._symlink(
                facts, cfg, "custom_prefix_symlink", cfg.primary_env, root=True
            ),
            self._no_symlink(facts, cfg),
        ]

    def _custom_prefix(self, facts: FeatureFacts) -> str:
        return f"/opt/{facts.primary_bin}-test"

    def _symlink(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        name: str,
        env: str,
        *,
        root: bool,
    ) -> GeneratedScenario:
        bin_ = facts.primary_bin
        custom_prefix = self._custom_prefix(facts)
        resolved_path = facts.resolved_bin_path(custom_prefix, bin_)
        link_dir = facts.symlink_root if root else facts.symlink_nonroot
        link_path = f"{link_dir}/{bin_}"

        scenario = base_scenario(
            [env],
            cfg,
            _FAMILY,
            options={"prefix": custom_prefix, "prefix_discovery": "symlink"},
        )
        scenario["tests"] = [name]

        checks: list[CheckItem] = [
            *checks_builtin.existence_triad(bin_, path=resolved_path),
            CheckItem(
                title=f"{bin_} --version succeeds at custom path",
                cmd=f"{resolved_path} {facts.version_flag}",
            ),
            *checks_builtin.symlink_present_checks(resolved_path, link_path),
            CheckItem(title=f"{bin_} resolves from PATH", cmd=f"command -v {bin_}"),
        ]
        functional = facts.functional
        if functional is not None:
            cmd_template, description = functional
            checks.append(
                checks_builtin.functional_check(
                    cmd_template,
                    f"{description} via custom path",
                    resolved_path,
                ),
            )
            checks.append(
                checks_builtin.functional_check(
                    cmd_template,
                    f"{description} via PATH",
                    bin_,
                ),
            )
        group = CheckGroup(
            description=f"prefix={custom_prefix}, prefix_discovery=symlink: binary "
            "installs at the custom prefix and a symlink is created at the default "
            "location.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _no_symlink(
        self, facts: FeatureFacts, cfg: GenerationConfig
    ) -> GeneratedScenario:
        name = "custom_prefix_no_symlink"
        bin_ = facts.primary_bin
        custom_prefix = self._custom_prefix(facts)
        resolved_path = facts.resolved_bin_path(custom_prefix, bin_)
        link_path = f"{facts.symlink_root}/{bin_}"

        scenario = base_scenario(
            [cfg.primary_env],
            cfg,
            _FAMILY,
            options={"prefix": custom_prefix, "prefix_discovery": "none"},
        )
        scenario["tests"] = [name]

        checks: list[CheckItem] = [
            *checks_builtin.existence_triad(bin_, path=resolved_path),
        ]
        functional = facts.functional
        if functional is not None:
            cmd_template, description = functional
            checks.append(
                checks_builtin.functional_check(
                    cmd_template,
                    f"{description} via custom path",
                    resolved_path,
                ),
            )
        checks.append(checks_builtin.symlink_absent_check(link_path))
        group = CheckGroup(
            description=f"prefix={custom_prefix}, prefix_discovery=none: binary "
            "installs at the custom prefix and no symlink is created.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})
