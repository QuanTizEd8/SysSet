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
# A deliberately *low* sentinel version. if_exists=update must upgrade the fake
# stub to the real target; a high sentinel (e.g. 9.9.9) is newer than every real
# release, so a feature whose update path refuses to downgrade (verified: pixi
# `info --extended` update declines when installed > target) leaves the stub in
# place and the "no longer the fake stub" check fails. 0.0.1 is older than any
# real release, so update always upgrades, while skip (unchanged) / fail
# (aborts) / reinstall (unconditional) are indifferent to the value.
_FAKE_VERSION = "0.0.1"

# Methods whose `if_exists=update` path operates on real installed state (e.g.
# `npm install --update` requires the actual package tree at PREFIX) and so
# cannot be satisfied by the cheap fake-stub seed — for these, if_exists_update
# seeds a genuine prior install instead. Overwrite-style methods
# (binary/source/package/cargo) update by reinstalling over the stub and need
# no real prior state.
_STATEFUL_UPDATE_METHODS = frozenset({"npm-bundled", "npm"})


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
            # Pass the pinned version (when any) so the pick is channel-aware:
            # reinstall/update pin `test_pins.pinned[0]`, an exact version that
            # must not land on a PM method that cannot resolve it.
            # Reinstall/update actually install the tool, so run them where the
            # tool installs (auto_install_env → cfg.npm_env for an npm-only
            # feature like install-pnpm/yarn, whose method is infeasible on the
            # bare primary env) and resolve the method against that env's
            # provisioning.
            install_env = facts.install_env or envselect.auto_install_env(
                facts, cfg, envs
            )
            prov = envselect.provisioning_for(install_env, cfg)
            pinned, _legacy = facts.test_pins
            method = envselect.first_feasible_method(
                facts,
                envs,
                install_env,
                allowed=facts.prefix_capable_methods,
                version=pinned[0] if pinned else None,
                **prov,
            )
            results.append(
                self._mutating(
                    "if_exists_reinstall", "reinstall", method, install_env, facts, cfg
                ),
            )
            results.append(
                self._mutating(
                    "if_exists_update", "update", method, install_env, facts, cfg
                ),
            )
        return results

    def _setup(self, facts: FeatureFacts) -> str:
        """Seed a fake stub script reporting `_FAKE_VERSION` at the default path."""
        path = facts.resolved_bin_path(facts.default_prefix_root, facts.primary_bin)
        flag = facts.version_flag
        fake_output = f"{facts.primary_bin}-{_FAKE_VERSION} (fake)"
        # mkdir -p first: default_prefix_root isn't always a pre-existing
        # directory like /usr/local — a feature whose own prefix root is a
        # dedicated, not-yet-created directory (e.g. /usr/local/cargo) would
        # otherwise fail here on a fresh container with no prior install.
        # Match "$*" (all args, space-joined) rather than "$1": a feature's
        # version flag can be multi-word (e.g. pixi's verify.args "info
        # --extended"), which the shell splits into $1="info" $2="--extended",
        # so a "$1" == "info --extended" test would never match and the stub
        # would report no version — breaking if_exists detection and the
        # "version unchanged/mutated" rechecks. "$*" == "info --extended"
        # matches, and still matches a single-word "--version".
        script = (
            f"mkdir -p {path.rsplit('/', 1)[0]}\n"
            f"printf '#!/usr/bin/env bash\\n"
            f'if [ "$*" = "{flag}" ]; then echo "{fake_output}"; exit 0; fi\\n'
            f"exit 0' > {path}\n"
            f"chmod +x {path}"
        )
        # Symlink into symlink_root when the prefix root isn't already on the
        # default PATH (e.g. /usr/local/go, unlike plain /usr/local): a real
        # prior install would have gone through prefix-discovery and left this
        # symlink; if_exists=skip/fail never re-run that step, so `command -v`
        # would otherwise wrongly report the tool as absent even though
        # detection (which checks the prefix path directly, not PATH) finds it.
        link_path = f"{facts.symlink_root}/{facts.primary_bin}"
        if link_path != path and not facts.symlink_skipped:
            script += f"\nmkdir -p {facts.symlink_root}\nln -sf {path} {link_path}"
        return script

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
        env: str,
        facts: FeatureFacts,
        cfg: GenerationConfig,
    ) -> GeneratedScenario:
        options: dict = {"if_exists": if_exists}
        if method is not None:
            options["method"] = method
        pinned, _legacy = facts.test_pins
        if pinned:
            options["version"] = pinned[0]
        scenario = base_scenario([env], cfg, _FAMILY, options=options)
        scenario["tests"] = [name]

        bin_ = facts.primary_bin
        resolved_path = facts.resolved_bin_path(facts.default_prefix_root, bin_)
        real_seed = if_exists == "update" and method in _STATEFUL_UPDATE_METHODS
        scenario["setup"] = (
            self._real_seed_setup(facts, method) if real_seed else self._setup(facts)
        )

        checks = [*checks_builtin.existence_triad(bin_, path=resolved_path)]
        if not real_seed:
            # Only meaningful when a fake stub was seeded: prove the mutate
            # replaced it. (With a real prior install there was never a stub.)
            checks.append(
                CheckItem(
                    title=f"{bin_} version is no longer the fake stub",
                    cmd=(
                        f"bash -c '! ({bin_} {facts.version_flag} 2>&1 | "
                        f'grep -q "{_FAKE_VERSION}")\''
                    ),
                ),
            )
        checks.append(checks_builtin.version_format_check(bin_, facts.version_flag))
        functional = facts.functional
        if functional is not None:
            cmd_template, description = functional
            checks.append(
                checks_builtin.functional_check(
                    cmd_template, description, resolved_path
                ),
            )
        seeded = "a real prior install" if real_seed else "an existing install"
        group = CheckGroup(
            description=f"if_exists={if_exists} replaces {seeded} with a "
            "real, working one.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _real_seed_setup(self, facts: FeatureFacts, method: str | None) -> str:
        """Seed a genuine prior install (stable, via `method`) for update tests.

        Runs the feature's own install.sh once so `if_exists=update` has real
        installed state to operate on — required by npm-bundled/npm, whose
        update path (`npm install --update`) needs the actual package tree.
        """
        method_env = f"METHOD={method} " if method is not None else ""
        return f"{method_env}sh /repo/src/{facts.feature_id}/install.sh"
