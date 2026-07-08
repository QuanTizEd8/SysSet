"""Custom-prefix + symlink-discovery scenario family.

Covers `custom_prefix_symlink`/`custom_prefix_no_symlink`/
`custom_prefix_symlink_nonroot`: install at a non-default prefix, verify
symlink discovery behaves as configured. Trigger: `_options.prefix.bins`
non-empty and symlinks aren't globally skipped.

`custom_prefix_symlink_nonroot` (standalone-only — devcontainer image builds
always run as root regardless of `remoteUser`, so there's no non-root mode to
target there) requires `standalone.user` to actually run the install as that
user, which `run.py` did not honor until it was fixed; the scenario was
dropped rather than shipped confirmed-broken. Now that the runner wires
`standalone.user` through to the install step, and the custom prefix's setup:
chown gives the target user write access without needing privileged
bookkeeping (see the `_FEAT_SHARE_DIR_NONROOT` fix in
`features/install.tmpl.bash`), it's safe to generate again.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.environments import resolve_attributes
from proman.test.gen import checks_builtin, envselect
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
        envs: dict,
    ) -> list[GeneratedScenario]:
        """Generate the root symlink, no-symlink, and non-root symlink scenarios."""
        # install_env overrides for a tool pre-installed on the standard envs
        # (bash): install/symlink scenarios must run where the tool is absent.
        root_env = facts.install_env or cfg.primary_env
        nonroot_env = facts.install_env_nonroot or cfg.nonroot_env
        results = [
            self._symlink(
                facts, cfg, envs, "custom_prefix_symlink", root_env, root=True
            ),
            self._no_symlink(facts, cfg, envs, root_env),
            self._symlink(
                facts,
                cfg,
                envs,
                "custom_prefix_symlink_nonroot",
                nonroot_env,
                root=False,
            ),
        ]
        return [r for r in results if r is not None]

    def _custom_prefix(self, facts: FeatureFacts) -> str:
        return f"/opt/{facts.primary_bin}-test"

    def _method_option(
        self,
        facts: FeatureFacts,
        envs: dict,
        env: str,
    ) -> dict | None:
        """Pin the prefix-capable method this custom-prefix scenario should use.

        Always an explicit `method:` — never `auto` — because a custom-prefix
        scenario must exercise a method that honors `--prefix`. Even without a
        declared `applies_when`, `auto` can resolve to `package`/
        `upstream-package` (e.g. install-rust), which install to a PM-managed
        location and ignore `--prefix`, so every path assertion would fail.
        `prefix_capable_methods` excludes the PM methods; the canonical-first
        feasible one is pinned. Returns `None` (caller skips) when none is
        feasible on `env` — a PM-only feature, or a compatible set all gated
        out here — since an unpinned scenario would assert an unused prefix.
        """
        method = envselect.first_feasible_method(
            facts, envs, env, allowed=facts.prefix_capable_methods
        )
        if method is None:
            return None
        return {"method": method}

    def _symlink(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
        name: str,
        env: str,
        *,
        root: bool,
    ) -> GeneratedScenario | None:
        bin_ = facts.primary_bin
        custom_prefix = self._custom_prefix(facts)
        resolved_path = facts.resolved_bin_path(custom_prefix, bin_)
        link_dir = facts.symlink_root if root else facts.symlink_nonroot
        link_path = f"{link_dir}/{bin_}"

        method_option = self._method_option(facts, envs, env)
        if method_option is None:
            return None
        scenario = base_scenario(
            [env],
            cfg,
            _FAMILY,
            options={
                "prefix": custom_prefix,
                "prefix_discovery": "symlink",
                **method_option,
            },
        )
        if not root:
            # /opt/... is outside the target user's home, so it needs to be
            # pre-created and chowned before a non-privileged install can write
            # to it — mirrors install-git/install-zsh's hand-written non-root
            # custom-prefix scenarios. devcontainer mode can't exercise this at
            # all (image builds always run as root), so force standalone-only
            # regardless of the family's configured modes.
            #
            # curl/ca-certificates are pre-installed here (as root, before the
            # su-wrapped install) because the non-root install has no privilege
            # to bootstrap a fetch tool itself — confirmed by a real Docker run
            # against install-jq, whose bootstrap needs curl to resolve
            # `version: stable` against the GitHub API. The pinned method's
            # build deps (e.g. install-zsh's build-essential/libncurses-dev for
            # method=source) are pre-installed for the same reason: a source
            # build needs a toolchain the non-root user can't apt-install.
            # Archive extractors (xz-utils/bzip2/unzip) are pre-installed for
            # the same reason: a .tar.xz binary release (install-node) needs xz,
            # and bootstrap__xz has no privilege-free path, so a non-root install
            # would otherwise fail to extract.
            pm = resolve_attributes(env, envs).get("plat.pm", "apt")
            build_pkgs = facts.build_packages(method_option["method"], pm)
            pkgs = " ".join(
                ["curl", "ca-certificates", "xz-utils", "bzip2", "unzip", *build_pkgs]
            )
            scenario["modes"] = ["standalone"]
            scenario["setup"] = (
                "retry apt-get update -qq\n"
                f"retry apt-get install -y --no-install-recommends {pkgs}\n"
                f"mkdir -p {custom_prefix}\n"
                f"chown vscode:vscode {custom_prefix}"
            )
            scenario["standalone"] = {"user": "vscode"}
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
        location = "default" if root else "non-root default"
        group = CheckGroup(
            description=f"prefix={custom_prefix}, prefix_discovery=symlink: binary "
            f"installs at the custom prefix and a symlink is created at the "
            f"{location} location.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _no_symlink(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
        env: str,
    ) -> GeneratedScenario | None:
        name = "custom_prefix_no_symlink"
        bin_ = facts.primary_bin
        custom_prefix = self._custom_prefix(facts)
        resolved_path = facts.resolved_bin_path(custom_prefix, bin_)
        link_path = f"{facts.symlink_root}/{bin_}"

        method_option = self._method_option(facts, envs, env)
        if method_option is None:
            return None
        scenario = base_scenario(
            [env],
            cfg,
            _FAMILY,
            options={
                "prefix": custom_prefix,
                "prefix_discovery": "none",
                **method_option,
            },
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
