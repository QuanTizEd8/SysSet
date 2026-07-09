"""`installer_dir` scenario: the download trace directory is populated.

Trigger: the feature declares a download method (binary/source/script) that
fetches assets through `uri__fetch_asset`, which — when `installer_dir` is set —
persists the release archive (and its checksum sidecar) under
`{installer_dir}/{archive,sidecar}/` instead of an auto-cleaned tmpdir.

Replaces the near-identical hand-written `installer_dir` scenario repeated
across install-gh/just/shellcheck/pixi/taskfile/fzf/lefthook/miniforge.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import context, default_checks, envselect
from proman.test.gen import outcome as outcome_mod
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, CheckItem, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "installer_dir"


@register
class InstallerDirRule:
    """Generates the `installer_dir` download-trace scenario."""

    family = _FAMILY
    check_generation = "full"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:  # noqa: ARG002
        """Whether the feature has a download method that populates installer_dir."""
        return bool(facts.download_methods)

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> list[GeneratedScenario]:
        """Generate the single `installer_dir` scenario for a download method."""
        env = facts.install_env or cfg.primary_env
        method = envselect.first_feasible_method(
            facts, envs, env, allowed=facts.download_methods
        )
        if method is None:
            return []
        idir = f"/tmp/{facts.primary_bin}-installer"  # noqa: S108 — test trace dir
        scenario = base_scenario(
            [env], cfg, _FAMILY, options={"method": method, "installer_dir": idir}
        )
        scenario["tests"] = [_FAMILY]

        ctx = context.for_env(env, envs, **envselect.provisioning_for(env, cfg))
        outcome = outcome_mod.compute(facts, ctx, method=method)
        # The install still has to succeed and land correctly...
        checks: list[CheckItem] = default_checks.build(facts, cfg, outcome)
        # ...and the trace directory must preserve the downloaded artifacts.
        checks.append(
            CheckItem(title="installer_dir exists", cmd=f"test -d {idir}"),
        )
        checks.append(
            CheckItem(
                title="release archive preserved in installer_dir",
                cmd=f"bash -c 'test -n \"$(ls -A {idir}/archive 2>/dev/null)\"'",
                debug=f"ls -la {idir}/ {idir}/archive/ 2>&1 || true",
            ),
        )
        if facts.has_sidecar:
            checks.append(
                CheckItem(
                    title="checksum sidecar preserved in installer_dir",
                    cmd=f"bash -c 'test -n \"$(ls -A {idir}/sidecar 2>/dev/null)\"'",
                    debug=f"ls -la {idir}/sidecar/ 2>&1 || true",
                ),
            )
        group = CheckGroup(
            description=f"installer_dir={idir}: the downloaded release archive"
            f"{' and its checksum sidecar' if facts.has_sidecar else ''} are "
            f"preserved in the trace directory after a method={method} install.",
            checks=checks,
        )
        return [
            GeneratedScenario(name=_FAMILY, scenario=scenario, checks={_FAMILY: group}),
        ]
