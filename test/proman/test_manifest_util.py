"""Tests for ospkg manifest option generation utilities."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from proman.manifest_util import (
    escape_devcontainer_default,
    generate_dep_trigger_specs,
    inject_dep_commands,
    serialize_manifest,
)
from proman.sync.install_script import _shell_val
from proman.sync.pipeline import _generate_metadata_json


def test_serialize_manifest_empty() -> None:
    """Empty or missing manifest content serializes to an empty string."""
    assert serialize_manifest({}) == ""
    assert serialize_manifest(None) == ""


def test_serialize_manifest_yaml() -> None:
    """Non-empty manifest dicts serialize to YAML with a trailing newline."""
    out = serialize_manifest({"packages": ["git"]})
    assert "packages:" in out
    assert "- git" in out
    assert out.endswith("\n")


def test_serialize_manifest_single_line_has_trailing_newline() -> None:
    """Even compact YAML must end with newline for inline manifest detection."""
    out = serialize_manifest({"packages": []})
    assert out == "packages: []\n"


def test_serialize_manifest_preserves_single_quotes_in_yaml() -> None:
    """YAML content with single quotes is serialized verbatim."""
    out = serialize_manifest({"packages": [{"name": "it's-fine"}]})
    assert "it's-fine" in out
    assert out.endswith("\n")


def test_serialize_manifest_preserves_dollar_signs() -> None:
    """Canonical manifest YAML keeps shell $ unescaped for install.bash defaults."""
    out = serialize_manifest(
        {
            "apt": {
                "scripts": 'if [[ -n "${_libdir}" ]]; then\n  true\nfi\n',
                "repos": ["baseurl=https://example/rpm/$releasever/$basearch"],
            },
        },
    )
    assert "${_libdir}" in out
    assert "$releasever" in out
    assert r"\$" not in out


def test_serialize_manifest_preserves_double_quotes() -> None:
    """Canonical manifest YAML keeps embedded double quotes unescaped."""
    out = serialize_manifest({"apt": {"scripts": 'echo "hello"\n'}})
    assert 'echo "hello"' in out
    assert r"\"" not in out


def test_escape_devcontainer_default_dollar_and_quote() -> None:
    """Devcontainer defaults escape $ and " but not already-escaped sequences."""
    raw = 'scripts: |\n  _libdir="$(find /usr/lib)"\n'
    escaped = escape_devcontainer_default(raw)
    assert r"_libdir=\"\$(find /usr/lib)\"" in escaped
    assert escape_devcontainer_default(r"\${PATH}") == r"\${PATH}"


def test_escape_devcontainer_default_env_file_roundtrip(tmp_path: Path) -> None:
    """Escaped defaults survive devcontainer-features.env sourcing."""
    raw = serialize_manifest(
        {
            "apt": {
                "scripts": (
                    "_libdir=\"$(find /usr/lib -type d -name '*-linux-*'"
                    ' 2>/dev/null | head -1)"\n'
                ),
            },
        },
    )
    escaped = escape_devcontainer_default(raw)
    env_file = tmp_path / "devcontainer-features.env"
    env_file.write_text(f'TEST_MANIFEST="{escaped}"\n', encoding="utf-8")
    bash_script = f"""
set -eu
# shellcheck source=/dev/null
. "{env_file}"
printf '%s' "$TEST_MANIFEST"
"""
    proc = subprocess.run(
        ["bash", "-c", bash_script],
        check=False,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout == raw


def test_install_bash_default_roundtrip_for_manifest() -> None:
    """Standalone install.bash defaults use clean YAML without devcontainer escapes."""
    raw = serialize_manifest({"apt": {"scripts": 'x="${_libdir}"\n'}})
    rhs = _shell_val(raw, "string")
    bash_script = f"""
set -eu
TEST_MANIFEST={rhs}
printf '%s' "$TEST_MANIFEST"
"""
    proc = subprocess.run(
        ["bash", "-c", bash_script],
        check=False,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout == raw


def test_generate_metadata_json_escapes_all_string_defaults() -> None:
    """devcontainer-feature.json escapes string defaults; metadata stays canonical."""
    manifest = serialize_manifest({"apt": {"scripts": 'x="${_libdir}"\n'}})
    metadata = {
        "options": {
            "ospkg_manifest_base_run": {
                "type": "string",
                "default": manifest,
            },
            "runtime_path": {
                "type": "string",
                "default": "${PATH}",
            },
            "zsh_cache_dir": {
                "type": "string",
                "default": "${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh",
            },
            "if_exists": {
                "type": "string",
                "default": "skip",
            },
        },
    }
    out = json.loads(
        _generate_metadata_json(metadata)[Path("devcontainer-feature.json")],
    )
    assert r"\${_libdir}" in out["options"]["ospkg_manifest_base_run"]["default"]
    assert out["options"]["runtime_path"]["default"] == r"\${PATH}"
    assert (
        out["options"]["zsh_cache_dir"]["default"]
        == r"\${XDG_CACHE_HOME:-\$HOME/.cache}/oh-my-zsh"
    )
    assert out["options"]["if_exists"]["default"] == "skip"


_CMD_MAP = {"git": "git", "make": "make", "ripgrep": "rg", "go": "go"}


def test_inject_bare_string_mapped_promoted_to_object() -> None:
    """A mapped bare-string package becomes ``{name, command}``."""
    out = inject_dep_commands({"packages": ["git", "sudo"]}, _CMD_MAP)
    assert out["packages"] == [{"name": "git", "command": "git"}, "sudo"]


def test_inject_object_name_mapped_gets_command() -> None:
    """A mapped package object with no version/command gets a command."""
    out = inject_dep_commands(
        {"packages": [{"name": "ripgrep", "when": {"plat.kernel": "linux"}}]},
        _CMD_MAP,
    )
    assert out["packages"][0]["command"] == "rg"
    assert out["packages"][0]["when"] == {"plat.kernel": "linux"}


def test_inject_skips_versioned_entry() -> None:
    """Version-pinned entries (self-install) are never guarded."""
    out = inject_dep_commands(
        {"packages": [{"name": "git", "version": "{feat.pm_version}"}]},
        _CMD_MAP,
    )
    assert "command" not in out["packages"][0]


def test_inject_respects_explicit_command_override() -> None:
    """An explicit ``command`` (incl. false/null opt-out) is left untouched."""
    for override in ("custom", False, None):
        out = inject_dep_commands(
            {"packages": [{"name": "git", "command": override}]},
            _CMD_MAP,
        )
        assert out["packages"][0]["command"] == override


def test_inject_skips_unmapped_names() -> None:
    """Packages not in the map are unchanged (no command key)."""
    out = inject_dep_commands({"packages": ["curl", {"name": "sudo"}]}, _CMD_MAP)
    assert out["packages"] == ["curl", {"name": "sudo"}]


def test_inject_guard_false_is_noop() -> None:
    """guard=False returns content unchanged (feature opt-out)."""
    content = {"packages": ["git"]}
    assert inject_dep_commands(content, _CMD_MAP, guard=False) == content


def test_inject_empty_map_is_noop() -> None:
    """An empty command map injects nothing."""
    content = {"packages": ["git"]}
    assert inject_dep_commands(content, {}) == content


def test_inject_none_and_empty_content() -> None:
    """None / empty content is returned as-is."""
    assert inject_dep_commands(None, _CMD_MAP) is None
    assert inject_dep_commands({}, _CMD_MAP) == {}


def test_inject_recurses_into_nested_when_groups() -> None:
    """Injection descends into nested ``{when, packages}`` group objects."""
    out = inject_dep_commands(
        {"packages": [{"when": {"plat.pm": "apt"}, "packages": ["make", "libc6-dev"]}]},
        _CMD_MAP,
    )
    nested = out["packages"][0]["packages"]
    assert nested == [{"name": "make", "command": "make"}, "libc6-dev"]


def test_inject_recurses_into_pm_subblocks() -> None:
    """Injection descends into PM-scoped ``{apt: {packages: …}}`` sub-blocks."""
    out = inject_dep_commands(
        {"apt": {"packages": ["make", "build-essential"]}},
        _CMD_MAP,
    )
    assert out["apt"]["packages"] == [
        {"name": "make", "command": "make"},
        "build-essential",
    ]


def test_inject_keys_on_logical_name_not_pm_override() -> None:
    """Commands key on the logical ``name``, ignoring per-PM name overrides."""
    out = inject_dep_commands(
        {"packages": [{"name": "go", "apt": "golang-go", "dnf": "golang"}]},
        _CMD_MAP,
    )
    pkg = out["packages"][0]
    assert pkg["command"] == "go"
    assert pkg["apt"] == "golang-go"  # PM override untouched


def test_inject_does_not_mutate_input() -> None:
    """The original content is never mutated (a deep copy is returned)."""
    content = {"packages": ["git", {"name": "make"}]}
    inject_dep_commands(content, _CMD_MAP)
    assert content == {"packages": ["git", {"name": "make"}]}


def test_inject_top_level_list_shorthand() -> None:
    """Array-shorthand content (a bare package list) is guarded too."""
    out = inject_dep_commands(["git", "sudo"], _CMD_MAP)
    assert out == [{"name": "git", "command": "git"}, "sudo"]


def test_generate_dep_trigger_specs_bundle() -> None:
    """Boolean option bundles emit a three-column trigger spec line."""
    metadata = {
        "_dependencies": {
            "run": {"option-archive_tools": {"packages": ["zip"]}},
        },
        "options": {"archive_tools": {"type": "boolean"}},
    }
    lines = generate_dep_trigger_specs(metadata)
    assert lines == [
        "archive_tools\tOSPKG_MANIFEST_OPTION_ARCHIVE_TOOLS\tARCHIVE_TOOLS",
    ]


def test_generate_dep_trigger_specs_skips_non_boolean() -> None:
    """Non-boolean options do not produce trigger specs."""
    metadata = {
        "_dependencies": {
            "run": {"option-jre": {"packages": ["openjdk"]}},
        },
        "options": {},
    }
    assert generate_dep_trigger_specs(metadata) == []


def test_generate_dep_trigger_specs_ignores_build_option_groups() -> None:
    """Option-bound manifests under build are ignored (run-only)."""
    metadata = {
        "_dependencies": {
            "run": {"option-sudo_access": {"packages": ["sudo"]}},
            "build": {"option-sudo_access": {"packages": ["sudo"]}},
        },
        "options": {"sudo_access": {"type": "boolean"}},
    }
    lines = generate_dep_trigger_specs(metadata)
    assert len(lines) == 1
    assert lines[0].startswith("sudo_access\t")
