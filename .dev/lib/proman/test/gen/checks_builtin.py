"""Small, named, composable check builders — one per reusable assertion shape.

Every rule composes checks from these functions rather than hand-writing
check dicts inline. This is what makes the generator easy to strengthen or fix
later: tightening a regex or fixing a PM-probe command is a one-function edit
here, applied everywhere that shape is used, instead of a hunt through every
rule (or, before this pipeline existed, every hand-written checks.yaml).
"""

from __future__ import annotations

import re
import shlex

from proman.test.gen.types import CheckItem

# Boundary-anchored so stray digits in unrelated output can't match, but
# tool-agnostic — no assumption about a `name-` version-string prefix. The
# optional `v` (bounded the same way as the digits themselves) covers the
# extremely common `vX.Y.Z` tag convention (e.g. shfmt's `v3.13.1`).
#
# The prefix boundary excludes digits/dots (rejecting a match embedded inside
# a longer numeric run, e.g. "142.5.6" must not match as "42.5.6") but
# deliberately allows a preceding letter: some tools glue their own name
# directly onto the version with no separator at all (`go version` prints
# "go1.26.4", not "go 1.26.4" or "go-1.26.4"). A stray letter+digits match in
# unrelated output is a negligible false-positive risk for a `--version`-style
# invocation's typically short, version-dominated output.
_VERSION_FORMAT_PATTERN = r"(^|[^0-9.])v?[0-9]+\.[0-9]+(\.[0-9]+)?([^0-9.]|$)"

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
    needed, unlike `sed 's/^tool-//'`-style parsing. `expected` is given
    without a `v` prefix (as declared in `test_pins`), but the tool's actual
    output may print it as `vX.Y.Z` (e.g. yq/shfmt), so the boundary allows
    an optional literal `v` directly before the expected value.
    """
    pattern = rf"(^|[^0-9.])v?{re.escape(expected)}([^0-9.]|$)"
    cmd = f"bash -c '{bin_name} {flag} 2>&1 | grep -Eq \"{pattern}\"'"
    return CheckItem(title=f"{bin_name} version is {expected}", cmd=cmd)


def functional_check(cmd_template: str, description: str, bin_value: str) -> CheckItem:
    """Render a feature's declared `_options.verify.functional.cmd`.

    Substitutes the literal `{bin}` placeholder with either a bare PATH name
    or an absolute custom-prefix path, depending on the calling scenario's
    context. Always wrapped in `bash -c '...'`: `codegen.py` renders a
    single-line `cmd` as literal, unquoted trailing words on the generated
    `check "title" ...` script line, so any shell metacharacters in the
    substituted command (pipes, redirects — the natural shape of most
    functional smoke tests, e.g. `echo "{}" | {bin} .`) would otherwise be
    parsed by the *script's* shell instead of executed as part of the check.
    Wrapping here means metadata authors never need to remember this and can
    declare `functional.cmd` as a plain, natural shell one-liner.
    """
    rendered = cmd_template.replace("{bin}", bin_value)
    return CheckItem(title=description, cmd=f"bash -c {shlex.quote(rendered)}")


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
    several PMs actually installed it). Duplicate commands (e.g. dnf and
    zypper both probe via `rpm -qf`) are deduplicated, preserving order.
    """
    cmds = list(
        dict.fromkeys(
            _PM_CHECK_CMD[pm].format(bin=bin_name, pkg_name=pkg_name)
            for pm in pms
            if pm in _PM_CHECK_CMD
        ),
    )
    title = "binary is package-manager-managed"
    if len(cmds) == 1:
        return CheckItem(title=title, cmd=cmds[0])
    return CheckItem(title=title, kind="multiple", min=1, cmd=cmds)


def installed_method_check(method: str, share_var: str) -> CheckItem:
    """Assert the framework recorded `method` as the installed method.

    Reads the `state/installed-method` file under the share dir env var
    (`_FEAT_SHARE_DIR_ROOT` or `_FEAT_SHARE_DIR_NONROOT`) that the test harness
    injects, so no project namespace is hardcoded. This is what verifies the
    *selected* method — the outcome model's central prediction — rather than
    just "some binary exists".
    """
    path = f'"${{{share_var}}}/state/installed-method"'
    return CheckItem(
        title=f"installed-method state is {method}",
        cmd=f"grep -Fqx {shlex.quote(method)} {path}",
    )


def path_export_present_check() -> CheckItem:
    """Assert the prefix PATH-export profile.d drop-in was written."""
    path = '"/etc/profile.d/${_FEAT_PROFILE_D_FILE}"'
    return CheckItem(
        title="PATH export profile.d file written",
        cmd=f"bash -c 'test -s {path}'",
    )


def path_export_absent_check() -> CheckItem:
    """Assert no prefix PATH-export profile.d drop-in was written."""
    path = '"/etc/profile.d/${_FEAT_PROFILE_D_FILE}"'
    return CheckItem(
        title="no PATH export profile.d file",
        cmd=f"bash -c '! test -e {path}'",
    )
