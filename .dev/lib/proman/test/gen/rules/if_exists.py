"""`if_exists_{skip,fail,reinstall,update}` scenarios.

Seeds a fake pre-existing stub binary reporting a fake "9.9.9" version, then
exercises each `if_exists` behavior against it. Trigger: the auto-generated
`if_exists` option exists (i.e. `_options.version` or `_options.method` is
declared).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import checks_builtin, envselect
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, CheckItem, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "if_exists"
_FAKE_VERSION = "9.9.9"


@register
class IfExistsRule:
    """Generates the if_exists_{skip,fail,reinstall,update} scenario family."""

    family = _FAMILY
    check_generation = "full"

    def applies(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,  # noqa: ARG002
    ) -> bool:
        """Whether this feature exposes the auto-generated `if_exists` option."""
        return facts.has_if_exists

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> list[GeneratedScenario]:
        """Generate skip/fail always; reinstall/update only when bins are declared."""
        results = [self._skip(facts, cfg), self._fail(facts, cfg)]
        # Reinstall/update require a PREFIX-attributable existing install to
        # detect correctly; without prefix.bins (e.g. git-clone-only
        # features), __detect_existing_method__ can't classify the fake stub
        # and if_exists=reinstall hard-fails with "installation method
        # unknown" — a real divergence, not a hypothetical, so these two
        # scenarios are skipped entirely in that case.
        if facts.bins:
            # Pin an explicit method (mirroring version_pinning.py) rather than
            # leaving it as "auto": verified via a real Docker run that
            # method=auto combined with a pinned `version` fails to resolve
            # during __reinstall_init__/__resolve_input_version__ even though
            # the exact same version resolves fine with an explicit method —
            # an auto-resolution edge case, not something to silently rely on.
            # Restricted to prefix.applies_when's compatible methods (when
            # declared) since reinstall/update detection is itself
            # PREFIX-path-based — the same reasoning as prefix_symlink.py.
            method = envselect.first_feasible_method(
                facts,
                envs,
                cfg.primary_env,
                allowed=facts.prefix_compatible_methods,
            )
            results.append(
                self._mutating("if_exists_reinstall", "reinstall", method, facts, cfg),
            )
            results.append(
                self._mutating("if_exists_update", "update", method, facts, cfg),
            )
        return results

    def _setup(self, facts: FeatureFacts) -> str:
        """Seed a fake stub script reporting `_FAKE_VERSION` at the default path."""
        path = facts.resolved_bin_path(facts.default_prefix_root, facts.primary_bin)
        flag = facts.version_flag
        fake_output = f"{facts.primary_bin}-{_FAKE_VERSION} (fake)"
        return (
            f"printf '#!/usr/bin/env bash\\n"
            f'if [ "${{1-}}" = "{flag}" ]; then echo "{fake_output}"; exit 0; fi\\n'
            f"exit 0' > {path}\n"
            f"chmod +x {path}"
        )

    def _skip(self, facts: FeatureFacts, cfg: GenerationConfig) -> GeneratedScenario:
        name = "if_exists_skip"
        scenario = base_scenario(
            [cfg.primary_env],
            cfg,
            _FAMILY,
            options={"method": "auto", "if_exists": "skip"},
        )
        scenario["setup"] = self._setup(facts)
        scenario["tests"] = [name]
        bin_ = facts.primary_bin
        checks = [
            CheckItem(
                title=f"{bin_} remains available after skip",
                cmd=f"command -v {bin_}",
            ),
            CheckItem(
                title=f"existing {bin_} version unchanged (skip did not reinstall)",
                cmd=(
                    f"bash -c '{bin_} {facts.version_flag} 2>&1 | "
                    f'grep -q "{_FAKE_VERSION}"\''
                ),
            ),
        ]
        group = CheckGroup(
            description="if_exists=skip leaves an already-installed tool untouched.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _fail(self, facts: FeatureFacts, cfg: GenerationConfig) -> GeneratedScenario:
        name = "if_exists_fail"
        # Pin the target version to the fake stub's own reported version: proves
        # if_exists=fail is unconditional (checked before any version comparison),
        # not silently skipped when the requested version happens to already match.
        scenario = base_scenario(
            [cfg.primary_env],
            cfg,
            _FAMILY,
            options={"if_exists": "fail", "version": _FAKE_VERSION},
        )
        scenario["setup"] = self._setup(facts)
        scenario["expect_install_failure"] = True
        scenario["tests"] = [name]
        bin_ = facts.primary_bin
        checks = [
            CheckItem(
                title="if_exists=fail exits with already-installed error",
                kind="install_failure",
                pattern="failing (if_exists=fail)",
            ),
            CheckItem(
                title=f"preinstalled {bin_} remains available",
                cmd=f"command -v {bin_}",
            ),
        ]
        group = CheckGroup(
            description="if_exists=fail aborts installation when the tool already "
            "exists.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _mutating(
        self,
        name: str,
        if_exists: str,
        method: str | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
    ) -> GeneratedScenario:
        options: dict = {"if_exists": if_exists}
        if method is not None:
            options["method"] = method
        pinned, _legacy = facts.test_pins
        if pinned:
            options["version"] = pinned[0]
        scenario = base_scenario([cfg.primary_env], cfg, _FAMILY, options=options)
        scenario["setup"] = self._setup(facts)
        scenario["tests"] = [name]

        bin_ = facts.primary_bin
        resolved_path = facts.resolved_bin_path(facts.default_prefix_root, bin_)
        checks = [
            *checks_builtin.existence_triad(bin_, path=resolved_path),
            CheckItem(
                title=f"{bin_} version is no longer the fake stub",
                cmd=(
                    f"bash -c '! ({bin_} {facts.version_flag} 2>&1 | "
                    f'grep -q "{_FAKE_VERSION}")\''
                ),
            ),
            checks_builtin.version_format_check(bin_, facts.version_flag),
        ]
        functional = facts.functional
        if functional is not None:
            cmd_template, description = functional
            checks.append(
                checks_builtin.functional_check(
                    cmd_template, description, resolved_path
                ),
            )
        group = CheckGroup(
            description=f"if_exists={if_exists} replaces an existing install with a "
            "real, working one.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})
