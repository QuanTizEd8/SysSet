"""`if_exists_{skip,fail,reinstall,update}` scenarios.

Seeds a fake pre-existing stub binary reporting a fake "9.9.9" version, then
exercises each `if_exists` behavior against it. Trigger: the auto-generated
`if_exists` option exists (i.e. `_options.version` or `_options.method` is
declared).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import checks_builtin, context, envselect
from proman.test.gen import outcome as outcome_mod
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

# if_exists=update always seeds a genuine prior install (via the feature's own
# install.sh) rather than the cheap fake stub. The stub has no real installed
# *method* state and its version is opaque to the feature's own detection —
# verified: pixi reads the stub as version 'unknown', so update reinstalls but
# cannot reason about the result, and npm/npm-bundled update literally needs the
# package tree at PREFIX. A real prior install gives update something coherent to
# operate on for every method. (skip/fail/reinstall keep the fast fake stub —
# they never compare versions.)


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
        # Git-clone-only features (install-ohmybash/install-ohmyzsh) have no
        # primary binary to stub, so the fake-stub setup below can't apply. The
        # framework detects an existing git-clone install purely by the presence
        # of `${_RESOLVED_PREFIX}/.git` (install.tmpl.bash __detect_existing_
        # {path,method}__), so seed that instead. reinstall/update are excluded:
        # they re-clone / `git pull`, which needs a genuine clone with the real
        # remote — not something a seeded `.git` dir can stand in for (a residual
        # gap best covered by a hand-written scenario if a feature wants it).
        if facts.is_git_clone_only:
            return [
                self._git_clone_skip(facts, cfg),
                self._git_clone_fail(facts, cfg),
            ]
        # Off-PATH features (skip-symlink+skip-export, e.g. install-homebrew):
        # the seeded stub lives at the prefix bin path but is NOT on the default
        # PATH, so skip/fail existence + version checks must probe the absolute
        # path, not a bare `command -v` (which runs in the non-login test shell).
        off_path = self._is_off_path(facts, cfg, envs, cfg.primary_env)
        results = [
            self._skip(facts, cfg, off_path=off_path),
            self._fail(facts, cfg, off_path=off_path),
        ]
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
            mut_off_path = self._is_off_path(
                facts, cfg, envs, install_env, method=method
            )
            results.append(
                self._mutating(
                    "if_exists_reinstall",
                    "reinstall",
                    method,
                    install_env,
                    facts,
                    cfg,
                    off_path=mut_off_path,
                ),
            )
            results.append(
                self._mutating(
                    "if_exists_update",
                    "update",
                    method,
                    install_env,
                    facts,
                    cfg,
                    off_path=mut_off_path,
                ),
            )
        return results

    def _is_off_path(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
        env: str,
        method: str | None = None,
    ) -> bool:
        """Whether the resolved install lands its binary off the default PATH.

        Reuses the outcome model (skip-symlink+skip-export with a non-standard
        bin dir), so if_exists asserts existence the same way `default` does.
        """
        ctx = context.for_env(env, envs, **envselect.provisioning_for(env, cfg))
        oc = outcome_mod.compute(facts, ctx, method=method)
        return oc is not None and not oc.on_path and oc.install_path is not None

    # ── git-clone-only variant ───────────────────────────────────────────────
    _GIT_CLONE_SENTINEL = ".devfeats-preexisting-sentinel"

    def _git_clone_setup(self, facts: FeatureFacts) -> str:
        """Seed a pre-existing git-clone install at the default prefix.

        The framework classifies an install as an existing git-clone purely by
        `${_RESOLVED_PREFIX}/.git` being a directory (install.tmpl.bash
        __detect_existing_path__/__detect_existing_method__), so a bare `.git`
        dir is a faithful stand-in. A sentinel file lets skip/fail assert the
        existing clone was left in place rather than wiped and re-cloned.
        """
        prefix = facts.default_prefix_root
        return f"mkdir -p {prefix}/.git\ntouch {prefix}/{self._GIT_CLONE_SENTINEL}"

    def _git_clone_skip(
        self, facts: FeatureFacts, cfg: GenerationConfig
    ) -> GeneratedScenario:
        name = "if_exists_skip"
        scenario = base_scenario(
            [cfg.primary_env],
            cfg,
            _FAMILY,
            options={"method": "auto", "if_exists": "skip"},
        )
        scenario["setup"] = self._git_clone_setup(facts)
        scenario["tests"] = [name]
        prefix = facts.default_prefix_root
        checks = [
            CheckItem(
                title="git-clone directory remains after skip",
                cmd=f"test -d {prefix}/.git",
            ),
            CheckItem(
                title="skip left the existing clone untouched (not re-cloned)",
                cmd=f"test -f {prefix}/{self._GIT_CLONE_SENTINEL}",
            ),
        ]
        group = CheckGroup(
            description="if_exists=skip leaves an already-cloned repository untouched.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _git_clone_fail(
        self, facts: FeatureFacts, cfg: GenerationConfig
    ) -> GeneratedScenario:
        name = "if_exists_fail"
        scenario = base_scenario(
            [cfg.primary_env],
            cfg,
            _FAMILY,
            options={"if_exists": "fail"},
        )
        scenario["setup"] = self._git_clone_setup(facts)
        scenario["expect_install_failure"] = True
        scenario["tests"] = [name]
        prefix = facts.default_prefix_root
        checks = [
            CheckItem(
                title="if_exists=fail exits with already-installed error",
                kind="install_failure",
                pattern="failing (if_exists=fail)",
            ),
            CheckItem(
                title="preexisting clone remains after fail",
                cmd=f"test -d {prefix}/.git",
            ),
        ]
        group = CheckGroup(
            description="if_exists=fail aborts when the repository is already cloned.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

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
        # Shebang is `#!/bin/sh`, never `#!/usr/bin/env bash`: for the bash
        # feature the stub IS the bash on PATH (it's seeded at the resolved bin
        # path, ahead of the system bash), so a bash shebang re-invokes the stub
        # itself — infinite recursion / fork bomb that hangs the job. /bin/sh is
        # always present and never the tool under test, and the stub body is
        # plain POSIX. (bash's own hand-written if_exists tests used /bin/sh.)
        script = (
            f"mkdir -p {path.rsplit('/', 1)[0]}\n"
            f"printf '#!/bin/sh\\n"
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

    def _avail_cmd(self, facts: FeatureFacts, *, off_path: bool) -> str:
        """Existence probe for the seeded stub: absolute path off-PATH, else PATH."""
        if off_path:
            path = facts.resolved_bin_path(facts.default_prefix_root, facts.primary_bin)
            return f"test -x {path}"
        return f"command -v {facts.primary_bin}"

    def _stub_invocation(self, facts: FeatureFacts, *, off_path: bool) -> str:
        """How to invoke the stub for a version probe (absolute path off-PATH)."""
        if off_path:
            return facts.resolved_bin_path(facts.default_prefix_root, facts.primary_bin)
        return facts.primary_bin

    def _skip(
        self, facts: FeatureFacts, cfg: GenerationConfig, *, off_path: bool = False
    ) -> GeneratedScenario:
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
        invoke = self._stub_invocation(facts, off_path=off_path)
        checks = [
            CheckItem(
                title=f"{bin_} remains available after skip",
                cmd=self._avail_cmd(facts, off_path=off_path),
            ),
            CheckItem(
                title=f"existing {bin_} version unchanged (skip did not reinstall)",
                cmd=(
                    f"bash -c '{invoke} {facts.version_flag} 2>&1 | "
                    f'grep -q "{_FAKE_VERSION}"\''
                ),
            ),
        ]
        group = CheckGroup(
            description="if_exists=skip leaves an already-installed tool untouched.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _fail(
        self, facts: FeatureFacts, cfg: GenerationConfig, *, off_path: bool = False
    ) -> GeneratedScenario:
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
        invoke = self._stub_invocation(facts, off_path=off_path)
        checks = [
            CheckItem(
                title="if_exists=fail exits with already-installed error",
                kind="install_failure",
                pattern="failing (if_exists=fail)",
            ),
            CheckItem(
                title=f"preinstalled {bin_} remains available",
                cmd=self._avail_cmd(facts, off_path=off_path),
            ),
            # Version-match idempotency: the requested version equals the
            # pre-existing one, yet fail still aborted AND left it untouched — no
            # "already at the desired version, silently proceed" fast-path. This
            # subsumes the hand-written version_match_idempotency (fail variant).
            CheckItem(
                title=f"preinstalled {bin_} version unchanged (fail did not reinstall)",
                cmd=(
                    f"bash -c '{invoke} {facts.version_flag} 2>&1 | "
                    f'grep -q "{_FAKE_VERSION}"\''
                ),
            ),
        ]
        group = CheckGroup(
            description="if_exists=fail aborts installation when the tool already "
            "exists, even when the requested version matches — leaving it untouched.",
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
        *,
        off_path: bool = False,
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
        # `update` always seeds a genuine prior install; so does `reinstall` for
        # an off-PATH feature. Off-PATH installs (install-homebrew) run their
        # installer as a dedicated non-root user into a user-owned prefix, and a
        # root-seeded fake stub leaves that prefix root-owned — the reinstall
        # then aborts with "Insufficient permissions" (verified in CI). A real
        # prior install (via the feature's own install.sh) establishes the
        # correct ownership so uninstall+reinstall works.
        real_seed = if_exists == "update" or off_path
        scenario["setup"] = (
            self._real_seed_setup(facts, method) if real_seed else self._setup(facts)
        )

        # existence_triad already probes the absolute path; the version checks
        # must invoke that absolute path too when the binary is off the default
        # PATH (a bare `command`/`bin` would not resolve in the test shell).
        invoke = resolved_path if off_path else bin_
        checks = [*checks_builtin.existence_triad(bin_, path=resolved_path)]
        if not real_seed:
            # Only meaningful when a fake stub was seeded: prove the mutate
            # replaced it. (With a real prior install there was never a stub.)
            checks.append(
                CheckItem(
                    title=f"{bin_} version is no longer the fake stub",
                    cmd=(
                        f"bash -c '! ({invoke} {facts.version_flag} 2>&1 | "
                        f'grep -q "{_FAKE_VERSION}")\''
                    ),
                ),
            )
        checks.append(checks_builtin.version_format_check(invoke, facts.version_flag))
        functional = facts.functional
        if functional is not None:
            cmd_template, description = functional
            checks.append(
                checks_builtin.functional_check(
                    cmd_template, description, resolved_path
                ),
            )
        # reinstall/update re-run the full install, re-recording installed-method.
        # A pinned-method root install records it under _FEAT_SHARE_DIR_ROOT
        # (default prefix, root env). Skip for off-PATH installs (homebrew runs
        # as a dedicated user, so the share dir is less certain).
        if method is not None and not off_path:
            checks.append(
                checks_builtin.installed_method_check(method, "_FEAT_SHARE_DIR_ROOT"),
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
