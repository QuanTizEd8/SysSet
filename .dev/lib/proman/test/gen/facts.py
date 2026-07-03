"""Pure extraction of test-generation-relevant facts from a feature's metadata.yaml.

Deliberately does no rule logic — only answers "what does this feature's
metadata declare". Keeping extraction and generation strictly separate means a
new rule family only needs a new `FeatureFacts` field when it reads a metadata
shape no existing rule already reads; it never needs to touch how any other
rule works.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class FeatureFacts:
    """Test-generation-relevant facts read from one feature's augmented metadata.yaml.

    Fields mirror `_options.*`/`_dependencies` sub-dicts near-verbatim (empty
    dict when the feature doesn't declare that block) rather than modeling
    every nuance up front — rules read the raw shape they need directly, and
    only genuinely reusable derived facts (below) get a property here.
    """

    feature_id: str
    public_options: dict = field(default_factory=dict)
    verify: dict = field(default_factory=dict)
    version: dict = field(default_factory=dict)
    methods: dict = field(default_factory=dict)
    prefix: dict = field(default_factory=dict)
    completions: dict | None = None
    dependencies: dict = field(default_factory=dict)
    system_requirements: dict = field(default_factory=dict)
    configure_users: bool = False

    @property
    def bins(self) -> list[str]:
        """`_options.prefix.bins`, or an empty list when undeclared."""
        return list(self.prefix.get("bins", ()))

    @property
    def primary_bin(self) -> str:
        """`{bin}`: `_options.verify.cmd` if declared, else `_options.prefix.bins[0]`.

        Mirrors the framework's own runtime resolution order in
        `install.tmpl.bash`'s lifecycle-script writer (`_FEAT_VERIFY_CMD` ->
        resolved-path var -> `_FEAT_CONTRACT_PRIMARY_BIN`), minus the
        install-time resolved-path fallback, which has no generation-time
        equivalent — it doesn't exist until an install actually runs.
        """
        cmd = self.verify.get("cmd")
        if cmd:
            return cmd
        bins = self.bins
        if bins:
            return bins[0]
        msg = (
            f"{self.feature_id}: cannot resolve a primary binary/command for test "
            "generation — declare _options.verify.cmd or _options.prefix.bins"
        )
        raise ValueError(msg)

    @property
    def version_flag(self) -> str:
        """`{flag}`: `version.flag`, else `verify.args`, else `--version`."""
        return self.version.get("flag") or self.verify.get("args") or "--version"

    @property
    def functional(self) -> tuple[str, str] | None:
        """`(cmd, description)` from `_options.verify.functional`, or None if absent."""
        func = self.verify.get("functional")
        if not func:
            return None
        return func["cmd"], func.get("description", "")

    @property
    def test_pins(self) -> tuple[list[str], list[str]]:
        """`(pinned, legacy)` version lists from `_options.version.test_pins`."""
        pins = self.version.get("test_pins", {})
        return list(pins.get("pinned", ())), list(pins.get("legacy", ()))

    @property
    def has_if_exists(self) -> bool:
        """Whether the auto-generated `if_exists` option exists on this feature.

        Mirrors `metadata.shared.yaml`'s own gating rule (present whenever
        `_options.version` or `_options.method` is declared).
        """
        return "if_exists" in self.public_options

    @property
    def method_names(self) -> list[str]:
        """Declared `_options.method` keys, in declaration order."""
        return list(self.methods.keys())

    def enum_values(self, option_name: str) -> list[str] | None:
        """Return declared enum values for one public option, e.g. "method".

        Exactly as argparse validates them at runtime — pulled from the same
        merged public `options` metadata.shared.yaml already computed
        (including the unconditional `auto` entry method carries), rather
        than re-derived. Returns None if this feature has no such option.
        """
        option = self.public_options.get(option_name)
        if not option or "enum" not in option:
            return None
        return [entry["value"] for entry in option["enum"]]

    def package_name(self, method: str) -> str:
        """Return the declared OS package name for a package-based method.

        `method` is "package" or "upstream-package"; the name comes from
        `_dependencies.run.method-<method>`. Falls back to `primary_bin` when
        undeclared or the first package entry is a bare string (no explicit
        name override).
        """
        run_deps = self.dependencies.get("run", {})
        packages = run_deps.get(f"method-{method}", {}).get("packages", [])
        if packages and isinstance(packages[0], dict) and packages[0].get("name"):
            return packages[0]["name"]
        return self.primary_bin


def extract(metadata: dict) -> FeatureFacts:
    """Extract FeatureFacts from one feature's augmented metadata.yaml dict.

    `metadata` is as returned by `proman.metadata.MetadataLoader().load(feature_id)`.
    """
    options = metadata.get("_options", {})
    return FeatureFacts(
        feature_id=metadata["id"],
        public_options=metadata.get("options", {}),
        verify=options.get("verify", {}),
        version=options.get("version", {}),
        methods=options.get("method", {}),
        prefix=options.get("prefix", {}),
        completions=options.get("completions"),
        dependencies=metadata.get("_dependencies", {}),
        system_requirements=metadata.get("_system_requirements", {}),
        configure_users=bool(options.get("configure_users", False)),
    )
