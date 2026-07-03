"""`completions_<shell>` + `completions_disabled` scenarios.

Trigger: `_options.completions` declared.

Completion install paths are fully standardized in `metadata.shared.yaml` and
implemented by the single shared `lib/shell.bash: shell__install_completion()`
— no per-feature hand-authored assertion is needed. Paths are resolved
statically at generation time from the chosen env's `os.id` attribute.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.environments import resolve_attributes
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, CheckItem, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "completions"

# lib/os.bash's os__platform(): canonical platform tag per raw os-release ID.
# Arch Linux has no ID_LIKE match and isn't Darwin, so os__platform's own
# fallback resolves it to "debian" — verified by reading os__platform in full,
# not assumed.
_PLATFORM_BY_OS_ID = {
    "debian": "debian",
    "ubuntu": "debian",
    "alpine": "alpine",
    "rhel": "rhel",
    "centos": "rhel",
    "fedora": "rhel",
    "rocky": "rhel",
    "almalinux": "rhel",
    "opensuse-leap": "suse",
    "opensuse-tumbleweed": "suse",
    "opensuse": "suse",
    "sles": "suse",
    "sle-micro": "suse",
    "macos": "macos",
    "arch": "debian",
}


def _zshdir(os_id: str) -> str:
    """Mirror `shell__detect_zshdir()`'s rhel/suse/macos-vs-default fallback."""
    platform = _PLATFORM_BY_OS_ID.get(os_id, "debian")
    return "/etc" if platform in ("rhel", "suse", "macos") else "/etc/zsh"


def _completion_checks(shell: str, bin_name: str, os_id: str) -> list[CheckItem]:
    if shell == "bash":
        path = f"/etc/bash_completion.d/{bin_name}"
        return [
            CheckItem(title="bash completion file exists", cmd=f"test -f {path}"),
            CheckItem(title="bash completion file is non-empty", cmd=f"test -s {path}"),
            CheckItem(
                title="bash completion file is valid bash", cmd=f"bash -n {path}"
            ),
        ]
    if shell == "zsh":
        path = f"{_zshdir(os_id)}/completions/_{bin_name}"
        return [CheckItem(title="zsh completion file exists", cmd=f"test -f {path}")]
    if shell == "fish":
        path = f"/usr/share/fish/vendor_completions.d/{bin_name}.fish"
        return [CheckItem(title="fish completion file exists", cmd=f"test -f {path}")]
    if shell == "nushell":
        path = f'"${{HOME}}/.config/nushell/autoload/{bin_name}.nu"'
        return [
            CheckItem(title="nushell completion file exists", cmd=f"test -f {path}")
        ]
    if shell == "elvish":
        path = '"${HOME}/.config/elvish/rc.elv"'
        return [
            CheckItem(
                title="elvish completion block present",
                cmd=f'grep -q "{bin_name} completion" {path}',
            ),
        ]
    return []


def _absence_checks(shell: str, bin_name: str, os_id: str) -> list[CheckItem]:
    """Negate `_completion_checks`'s existence assertion, for `completions_disabled`.

    None of the underlying commands (`test -f ...` / elvish's `grep -q "..." "..."`)
    use single quotes, so uniformly wrapping in `bash -c '! (...)'` is always safe —
    no need to special-case by command shape.
    """
    existence_check = _completion_checks(shell, bin_name, os_id)[0]
    return [
        CheckItem(
            title=f"no {shell} completion file",
            cmd=f"bash -c '! ({existence_check['cmd']})'",
        ),
    ]


@register
class CompletionsRule:
    """Generates one scenario per declared completion shell, plus a negative one."""

    family = _FAMILY
    check_generation = "full"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:  # noqa: ARG002
        """Whether this feature declares `_options.completions`."""
        return bool(facts.completions)

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> list[GeneratedScenario]:
        """One scenario per declared shell, plus the `completions_disabled` negative."""
        shells = (facts.completions or {}).get("shells", [])
        env = cfg.primary_env
        os_id = resolve_attributes(env, envs).get("os.id", "ubuntu")
        results = [
            self._shell_scenario(shell, env, os_id, facts, cfg) for shell in shells
        ]
        results.append(self._disabled_scenario(shells, env, os_id, facts, cfg))
        return results

    def _shell_scenario(
        self,
        shell: str,
        env: str,
        os_id: str,
        facts: FeatureFacts,
        cfg: GenerationConfig,
    ) -> GeneratedScenario:
        name = f"completions_{shell}"
        scenario = base_scenario(
            [env],
            cfg,
            _FAMILY,
            options={"shell_completions": shell},
        )
        scenario["tests"] = [name]
        checks = _completion_checks(shell, facts.primary_bin, os_id)
        group = CheckGroup(
            description=f"shell_completions={shell}: completion file is installed.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _disabled_scenario(
        self,
        shells: list[str],
        env: str,
        os_id: str,
        facts: FeatureFacts,
        cfg: GenerationConfig,
    ) -> GeneratedScenario:
        name = "completions_disabled"
        scenario = base_scenario(
            [env],
            cfg,
            _FAMILY,
            options={"shell_completions": ""},
        )
        scenario["tests"] = [name]
        checks: list[CheckItem] = []
        for shell in shells:
            checks.extend(_absence_checks(shell, facts.primary_bin, os_id))
        group = CheckGroup(
            description="shell_completions='': no completion files are installed.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})
