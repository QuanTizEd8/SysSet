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

_ALL_PMS = ["apt", "dnf", "zypper", "apk", "pacman"]


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


def test_package_name_resolves_pm_keyed_brew_shape() -> None:
    """A PM-keyed `method-package.brew.packages` resolves the brew formula name.

    install-taskfile nests its Homebrew formula under `method-package.brew`
    (not the flat `method-package.packages`), with `{name: task, brew: go-task}`
    — so the brew formula is `go-task`, not the binary `task`.
    """
    facts = FeatureFacts(
        feature_id="install-taskfile",
        verify={"cmd": "task"},
        methods={"package": {}},
        prefix={"bins": ["task"]},
        dependencies={
            "run": {
                "method-package": {
                    "brew": {"packages": [{"name": "task", "brew": "go-task"}]},
                },
            },
        },
    )
    assert facts.package_name("package", "brew") == "go-task"


def test_brew_package_detects_cask_and_strips_version_template() -> None:
    """A cask entry is detected and its version-templated name reduced to a base."""
    facts = FeatureFacts(
        feature_id="install-claude",
        verify={"cmd": "claude"},
        methods={"package": {}},
        prefix={"bins": ["claude"]},
        dependencies={
            "run": {
                "method-package": {
                    "brew": {
                        "casks": [
                            "{feat.version_input==latest?claude-code@latest:claude-code}",
                        ],
                    },
                },
            },
        },
    )
    assert facts.brew_package() == ("claude-code", True)


def test_brew_package_formula_pm_keyed_and_flat() -> None:
    """brew_package returns (formula, False) for both PM-keyed and flat shapes."""
    taskfile = FeatureFacts(
        feature_id="install-taskfile",
        verify={"cmd": "task"},
        methods={"package": {}},
        prefix={"bins": ["task"]},
        dependencies={
            "run": {
                "method-package": {
                    "brew": {"packages": [{"name": "task", "brew": "go-task"}]},
                },
            },
        },
    )
    assert taskfile.brew_package() == ("go-task", False)
    rust = FeatureFacts(
        feature_id="install-rust",
        verify={"cmd": "rustc"},
        methods={"package": {}},
        prefix={"bins": ["rustc"]},
        dependencies={"run": {"method-package": {"packages": [{"name": "rustup"}]}}},
    )
    assert rust.brew_package() == ("rustup", False)


def test_brew_managed_check_has_prefix_and_name_probes() -> None:
    """brew_managed_check is min:1 of a prefix probe OR a `brew list` name probe.

    The prefix probe (binary under `$(brew --prefix)`) covers CLI formulae/casks
    name-independently; the `brew list --formula|--cask <name>` probe covers a
    manager formula (rustup) whose binary lands outside the brew prefix. Either
    passing proves brew management.
    """
    item = checks_builtin.brew_managed_check("rustc", "rustup", is_cask=False)
    assert item["kind"] == "multiple"
    assert item["min"] == 1
    probes = item["cmd"]
    assert any('"$(command -v rustc)" == "$(brew --prefix)"/*' in p for p in probes)
    assert any("brew list --formula rustup" in p for p in probes)


def test_brew_managed_check_uses_cask_flag_for_casks() -> None:
    """A cask uses `brew list --cask`, a formula `brew list --formula`."""
    cask = checks_builtin.brew_managed_check("claude", "claude-code", is_cask=True)
    assert any("brew list --cask claude-code" in p for p in cask["cmd"])


def test_installed_method_check_either_scope_probes_both_share_dirs() -> None:
    """The either-scope check accepts the state under root OR nonroot share dir.

    A system-prefix macOS install records under _FEAT_SHARE_DIR_ROOT, but a
    user-home-prefix one (install-rust's ${HOME}/.cargo) records under
    _FEAT_SHARE_DIR_NONROOT — accept either.
    """
    item = checks_builtin.installed_method_check_either_scope("package")
    cmd = item["cmd"]
    assert item["title"] == "installed-method state is package"
    assert "_FEAT_SHARE_DIR_ROOT" in cmd
    assert "_FEAT_SHARE_DIR_NONROOT" in cmd
    assert "||" in cmd
    # The nonroot value embeds a literal ${HOME}; the probe must re-expand it
    # (a single expansion would leave ${HOME} unresolved and miss the file).
    assert 'eval "_n=${_FEAT_SHARE_DIR_NONROOT}"' in cmd


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


def test_build_packages_filters_conditional_deps() -> None:
    """Conditional build deps: codename-gated filtered, feat.* kept, names extracted."""
    codename = "os.version_codename"
    facts = FeatureFacts(
        feature_id="install-fixture",
        verify={"cmd": "git"},
        methods={"source": {}},
        dependencies={
            "build": {
                "method-source": {
                    "apt": {
                        "packages": [
                            "build-essential",
                            {
                                "name": "libpcre2-posix3",
                                "when": {codename: ["noble", "jammy"]},
                            },
                            {
                                "name": "libpcre2-posix0",
                                "when": {codename: ["bionic", "buster"]},
                            },
                            {
                                "name": "cargo",
                                "when": {"feat.version": {"gte": "2.55"}},
                            },
                        ],
                    },
                },
            },
        },
    )
    noble = {"os.version_codename": "noble", "plat.pm": "apt"}
    pkgs = facts.build_packages("source", "apt", attrs=noble)
    assert "build-essential" in pkgs  # bare string
    assert "libpcre2-posix3" in pkgs  # codename matches noble
    assert "libpcre2-posix0" not in pkgs  # codename does not match
    assert "cargo" in pkgs  # feat.* condition can't be evaluated -> kept
    # No dict leaked into the list (would break " ".join in the setup).
    assert all(isinstance(p, str) for p in pkgs)
