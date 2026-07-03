"""Small, named, composable check builders — one per reusable assertion shape.

Every rule composes checks from these functions rather than hand-writing
check dicts inline. This is what makes the generator easy to strengthen or fix
later: tightening a regex or fixing a PM-probe command is a one-function edit
here, applied everywhere that shape is used, instead of a hunt through every
rule (or, before this pipeline existed, every hand-written checks.yaml).
"""

from __future__ import annotations

import re

from proman.test.gen.types import CheckItem

# Boundary-anchored so stray digits in unrelated output can't match, but
# tool-agnostic — no assumption about a `name-` version-string prefix.
_VERSION_FORMAT_PATTERN = r"(^|[^0-9A-Za-z.])[0-9]+\.[0-9]+(\.[0-9]+)?([^0-9.]|$)"

# One file-ownership/name-existence probe per `plat.pm` value, verified against
# real checks.yaml usage and lib/ospkg.bash's own ospkg__is_managed(). The
# dpkg/rpm/pacman variants need the resolved binary *path* (file-ownership
# queries); apk/brew need the OS *package name*, which can differ from the
# binary name (e.g. `github-cli` package -> `gh` binary).
_PM_CHECK_CMD: dict[str, str] = {
    "apt": "bash -c 'dpkg -S \"$(command -v {bin})\" >/dev/null 2>&1'",
    "dnf": "bash -c 'rpm -qf \"$(command -v {bin})\" >/dev/null 2>&1'",
    "zypper": "bash -c 'rpm -qf \"$(command -v {bin})\" >/dev/null 2>&1'",
    "apk": "bash -c 'apk info -e {pkg_name} >/dev/null 2>&1'",
    "pacman": "bash -c 'pacman -Qo \"$(command -v {bin})\" >/dev/null 2>&1'",
    "brew": "bash -c 'brew list {pkg_name} >/dev/null 2>&1'",
}


def existence_triad(bin_name: str, *, path: str | None = None) -> list[CheckItem]:
    """Build the existence + executable check pair.

    PATH-based (`{bin} is on PATH` + `... is executable`) when `path` is
    omitted, or resolved-path-based (`{bin} binary is at {path}` + `... is
    executable`) when given.
    """
    if path is None:
        return [
            CheckItem(title=f"{bin_name} is on PATH", cmd=f"command -v {bin_name}"),
            CheckItem(
                title=f"{bin_name} binary is executable",
                cmd=f"bash -c 'test -x \"$(command -v {bin_name})\"'",
            ),
        ]
    return [
        CheckItem(title=f"{bin_name} binary is at {path}", cmd=f"test -f {path}"),
        CheckItem(title=f"{bin_name} binary is executable", cmd=f"test -x {path}"),
    ]


def version_format_check(bin_name: str, flag: str) -> CheckItem:
    r"""Build a generic "reports a semver-shaped version" check.

    No expected value, so it works for `default`/un-pinned scenarios.
    Anchored so it can't match a stray digit sequence in unrelated output
    (unlike a bare `[0-9]+\.[0-9]+`).
    """
    cmd = f"bash -c '{bin_name} {flag} 2>&1 | grep -Eq \"{_VERSION_FORMAT_PATTERN}\"'"
    return CheckItem(title=f"{bin_name} reports a version", cmd=cmd)


def version_exact_check(bin_name: str, flag: str, expected: str) -> CheckItem:
    """Build a check cross-validating the installed version against `expected`.

    Uses boundary-anchored substring match — no per-tool prefix-stripping
    needed, unlike `sed 's/^tool-//'`-style parsing.
    """
    pattern = rf"(^|[^0-9A-Za-z.]){re.escape(expected)}([^0-9.]|$)"
    cmd = f"bash -c '{bin_name} {flag} 2>&1 | grep -Eq \"{pattern}\"'"
    return CheckItem(title=f"{bin_name} version is {expected}", cmd=cmd)


def functional_check(cmd_template: str, description: str, bin_value: str) -> CheckItem:
    """Render a feature's declared `_options.verify.functional.cmd`.

    Substitutes the literal `{bin}` placeholder with either a bare PATH name
    or an absolute custom-prefix path, depending on the calling scenario's
    context.
    """
    return CheckItem(title=description, cmd=cmd_template.replace("{bin}", bin_value))


def symlink_present_checks(target_path: str, link_path: str) -> list[CheckItem]:
    """Positive pair: a symlink exists at `link_path` and resolves to `target_path`."""
    return [
        CheckItem(title=f"symlink exists at {link_path}", cmd=f"test -L {link_path}"),
        CheckItem(
            title=f"symlink resolves to {target_path}",
            cmd=f'bash -c \'[ "$(readlink -f {link_path})" = "{target_path}" ]\'',
        ),
    ]


def symlink_absent_check(link_path: str) -> CheckItem:
    """Negative counterpart: no symlink (and nothing else) at `link_path`."""
    cmd = f"bash -c '! test -L {link_path} && ! test -e {link_path}'"
    return CheckItem(title=f"no symlink at {link_path}", cmd=cmd)


def pm_managed_check(bin_name: str, pkg_name: str, pms: list[str]) -> CheckItem:
    """Build a "binary is package-manager-managed" check.

    Uses only the probe commands for `pms` (the package managers actually
    feasible for the selected env(s)) — a single `check` when only one PM is
    feasible, else `kind: multiple, min: 1` (passes regardless of which of
    several PMs actually installed it).
    """
    cmds = [
        _PM_CHECK_CMD[pm].format(bin=bin_name, pkg_name=pkg_name)
        for pm in pms
        if pm in _PM_CHECK_CMD
    ]
    title = "binary is package-manager-managed"
    if len(cmds) == 1:
        return CheckItem(title=title, cmd=cmds[0])
    return CheckItem(title=title, kind="multiple", min=1, cmd=cmds)
