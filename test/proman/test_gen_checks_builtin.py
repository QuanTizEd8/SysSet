"""Tests for checks_builtin probe construction.

Guards the pm-managed probes against a codegen interaction: `kind: multiple`
cmds are emitted inside double quotes (codegen._dquote), so the *outer* shell
expands any `$var`/`${...}` before the string reaches `bash -c`. A probe that
referenced an intermediate shell variable expanded it to empty and silently
failed on every distro (a real regression). Only `$(command -v ...)` survives
that double-quoting, so probes must use command substitution + literals, never
a bare parameter/variable expansion.
"""

from __future__ import annotations

import re

from proman.test.codegen import _dquote
from proman.test.gen import checks_builtin
from proman.test.gen.facts import FeatureFacts

_ALL_PMS = ["apt", "dnf", "zypper", "apk", "pacman", "brew"]


def test_package_name_resolves_per_pm() -> None:
    """A package whose name differs per PM resolves correctly for each (oras)."""
    facts = FeatureFacts(
        feature_id="install-fixture",
        verify={"cmd": "oras"},
        methods={"package": {}},
        dependencies={
            "run": {
                "method-package": {
                    "packages": [
                        {"name": "golang-oras", "when": {"plat.pm": ["dnf", "yum"]}},
                        {
                            "name": "oras",
                            "apk": "oras-cli",
                            "when": {"plat.pm": ["apk", "apt", "brew"]},
                        },
                    ],
                },
            },
        },
    )
    assert facts.package_name("package", "dnf") == "golang-oras"
    assert facts.package_name("package", "apk") == "oras-cli"  # per-PM override
    assert facts.package_name("package", "apt") == "oras"  # name, no override
    assert facts.package_name("package") == "golang-oras"  # first, no pm


def _probe_cmds() -> list[str]:
    item = checks_builtin.pm_managed_check(
        "zsh", dict.fromkeys(_ALL_PMS, "zsh"), _ALL_PMS
    )
    cmd = item["cmd"]
    return cmd if isinstance(cmd, list) else [cmd]


def test_pm_probes_use_no_bare_shell_variables() -> None:
    """No probe references a shell var/param expansion (killed by codegen quoting)."""
    # `$(` command substitution is fine (survives the outer double quotes);
    # a bare `$name` or `${...}` is not — the outer shell would expand it first.
    bad = re.compile(r"\$\{|\$[A-Za-z_]")
    for cmd in _probe_cmds():
        assert not bad.search(cmd), f"probe uses outer-shell-expanded var: {cmd!r}"


def test_apt_probe_has_usrmerge_fallback() -> None:
    """Apt retries the literal /bin path for usrmerged shell-package DB records."""
    apt = next(c for c in _probe_cmds() if "dpkg" in c)
    assert "/bin/zsh" in apt
    # Round-trips through codegen's double-quoting without introducing a var.
    assert "${" not in _dquote(apt)
