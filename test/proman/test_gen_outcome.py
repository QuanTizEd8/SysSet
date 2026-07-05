"""Tests for the expected-outcome model.

Pins the install-outcome predictions the generator's richer checks rely on:
resolved method, install location, symlink/PATH-export decisions per
`prefix_discovery`, PM-managed vs prefix installs, and the non-root default
prefix.
"""

from __future__ import annotations

from proman.test.gen import outcome
from proman.test.gen.facts import FeatureFacts
from proman.test.gen.method_resolver import ResolveContext

UBUNTU = {
    "os.id": "ubuntu",
    "plat.pm": "apt",
    "plat.kernel": "linux",
    "plat.machine_release": ["amd64", "arm64"],
}


def _facts(
    methods: dict,
    *,
    bins: list[str] | None = None,
    prefix: dict | None = None,
) -> FeatureFacts:
    prefix = dict(prefix or {})
    if bins is not None:
        prefix.setdefault("bins", bins)
    return FeatureFacts(
        feature_id="install-fixture",
        verify={"cmd": "tool"} if bins is None else {},
        methods=methods,
        prefix=prefix,
    )


# --- prefix method: default prefix, auto discovery --------------------------


def test_binary_default_prefix_auto_no_symlink() -> None:
    """A default-prefix binary install (on PATH) needs no symlink/export."""
    facts = _facts(
        {"binary": {"when": {"plat.machine_release": ["amd64", "arm64"]}}},
        bins=["tool"],
    )
    out = outcome.compute(facts, ResolveContext(attrs=UBUNTU))
    assert out is not None
    assert out.method == "binary"
    assert out.install_path == "/usr/local/bin/tool"
    assert out.symlink is None
    assert out.path_export is False
    assert out.on_path is True
    assert out.share_dir_var == "_FEAT_SHARE_DIR_ROOT"


# --- prefix method: custom prefix -------------------------------------------


def test_custom_prefix_symlink() -> None:
    """A custom prefix with discovery=symlink links /usr/local/bin to it."""
    facts = _facts({"binary": {}}, bins=["tool"])
    out = outcome.compute(
        facts,
        ResolveContext(attrs=UBUNTU),
        method="binary",
        prefix="/opt/tool-test",
        prefix_discovery="symlink",
    )
    assert out is not None
    assert out.install_path == "/opt/tool-test/bin/tool"
    assert out.symlink is not None
    assert out.symlink.link_path == "/usr/local/bin/tool"
    assert out.symlink.target == "/opt/tool-test/bin/tool"
    assert out.path_export is False


def test_custom_prefix_none_no_symlink() -> None:
    """discovery=none suppresses the symlink and asserts it absent."""
    facts = _facts({"binary": {}}, bins=["tool"])
    out = outcome.compute(
        facts,
        ResolveContext(attrs=UBUNTU),
        method="binary",
        prefix="/opt/tool-test",
        prefix_discovery="none",
    )
    assert out is not None
    assert out.symlink is None
    assert out.no_symlink_at == "/usr/local/bin/tool"


def test_custom_prefix_auto_creates_symlink() -> None:
    """discovery=auto with a not-on-PATH custom prefix creates a symlink."""
    facts = _facts({"binary": {}}, bins=["tool"])
    out = outcome.compute(
        facts,
        ResolveContext(attrs=UBUNTU),
        method="binary",
        prefix="/opt/tool-test",
        prefix_discovery="auto",
    )
    assert out is not None
    assert out.symlink is not None
    assert out.symlink.link_path == "/usr/local/bin/tool"


def test_discovery_shell_writes_export_not_symlink() -> None:
    """discovery=shell writes a PATH export and no symlink."""
    facts = _facts({"binary": {}}, bins=["tool"])
    out = outcome.compute(
        facts,
        ResolveContext(attrs=UBUNTU),
        method="binary",
        prefix="/opt/tool-test",
        prefix_discovery="shell",
    )
    assert out is not None
    assert out.symlink is None
    assert out.path_export is True


def test_discovery_all_symlink_and_export() -> None:
    """discovery=all writes both a symlink and a PATH export."""
    facts = _facts({"binary": {}}, bins=["tool"])
    out = outcome.compute(
        facts,
        ResolveContext(attrs=UBUNTU),
        method="binary",
        prefix="/opt/tool-test",
        prefix_discovery="all",
    )
    assert out is not None
    assert out.symlink is not None
    assert out.path_export is True


# --- non-root ----------------------------------------------------------------


def test_nonroot_custom_prefix_symlinks_into_local_bin() -> None:
    """A non-root custom-prefix install links ~/.local/bin + non-root state."""
    facts = _facts({"binary": {}}, bins=["tool"])
    out = outcome.compute(
        facts,
        ResolveContext(attrs=UBUNTU, privileged=False),
        method="binary",
        prefix="/opt/tool-test",
        prefix_discovery="symlink",
    )
    assert out is not None
    assert out.symlink is not None
    assert out.symlink.link_path == "~/.local/bin/tool"
    assert out.share_dir_var == "_FEAT_SHARE_DIR_NONROOT"


# --- PM methods --------------------------------------------------------------


def test_package_is_pm_managed_no_prefix_path() -> None:
    """A package install is PM-managed: no predictable path, no symlink."""
    facts = _facts({"package": {}}, bins=["tool"])
    out = outcome.compute(facts, ResolveContext(attrs=UBUNTU), method="package")
    assert out is not None
    assert out.method == "package"
    assert out.pm_managed is True
    assert out.install_path is None
    assert out.symlink is None
    assert out.on_path is True


# --- auto resolution + feasibility ------------------------------------------


def test_auto_resolves_method_and_records_it() -> None:
    """method=None resolves via the auto-resolver; the outcome names it."""
    facts = _facts(
        {
            "package": {},
            "binary": {"when": {"plat.machine_release": ["amd64", "arm64"]}},
        },
        bins=["tool"],
    )
    out = outcome.compute(facts, ResolveContext(attrs=UBUNTU))
    assert out is not None
    assert out.method == "binary"  # binary beats package in canonical order


def test_infeasible_request_returns_none() -> None:
    """An explicit method that isn't feasible under ctx yields None."""
    facts = _facts({"package": {}}, bins=["tool"])
    nonroot = ResolveContext(attrs=UBUNTU, privileged=False)
    assert outcome.compute(facts, nonroot, method="package") is None


def test_version_is_carried_through() -> None:
    """A resolved version is carried onto the outcome for cross-validation."""
    facts = _facts({"binary": {}}, bins=["tool"])
    out = outcome.compute(
        facts, ResolveContext(attrs=UBUNTU), method="binary", version="1.2.3"
    )
    assert out is not None
    assert out.version == "1.2.3"


# --- git-clone ---------------------------------------------------------------


def test_git_clone_outcome_is_a_directory() -> None:
    """A git-clone install yields a directory outcome, not a binary path."""
    facts = _facts({"git-clone": {}}, prefix={"root": "/opt/repo"})
    out = outcome.compute(
        facts, ResolveContext(attrs=UBUNTU, has_git=True), method="git-clone"
    )
    assert out is not None
    assert out.git_clone is True
    assert out.install_dir == "/opt/repo"
    assert out.install_path is None
