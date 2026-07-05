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
    def default_prefix_root(self) -> str:
        """`_options.prefix.root`, default `/usr/local`."""
        return self.prefix.get("root", "/usr/local")

    @property
    def default_prefix_nonroot(self) -> str:
        """`_options.prefix.nonroot`, default `${HOME}/.local`."""
        return self.prefix.get("nonroot", "${HOME}/.local")

    @property
    def bin_dir(self) -> str:
        """`_options.prefix.bin_dir`, default `bin`."""
        return self.prefix.get("bin_dir", "bin")

    @property
    def symlink_root(self) -> str:
        """Root symlink target, default `/usr/local/bin` (ignores custom `prefix`)."""
        return self.prefix.get("symlink", {}).get("root", "/usr/local/bin")

    @property
    def symlink_nonroot(self) -> str:
        """Non-root symlink target, default `~/.local/bin`."""
        return self.prefix.get("symlink", {}).get("nonroot", "~/.local/bin")

    @property
    def symlink_skipped(self) -> bool:
        """Whether `_options.prefix.symlink.skip` suppresses symlink creation."""
        return bool(self.prefix.get("symlink", {}).get("skip", False))

    @property
    def prefix_compatible_methods(self) -> list[str] | None:
        """Method names allowed by `_options.prefix.applies_when`, or None.

        `applies_when` restricts prefix machinery to specific install methods
        (e.g. binary/npm but not package/upstream-package, which install via
        the OS package manager with no PREFIX concept — `--prefix` is
        silently ignored outside these methods). `None` means no restriction
        declared, so prefix always applies (jq's shape). Every current
        real-world `applies_when` across the project is a single-key
        `method: [...]` condition (verified project-wide), so this only
        reads that key — the schema technically allows other option names in
        `applies_when`, but nothing uses that shape today.
        """
        applies_when = self.prefix.get("applies_when")
        if not applies_when:
            return None
        methods: list[str] = []
        for clause in applies_when:
            methods.extend(clause.get("method", ()))
        return methods

    @property
    def prefix_capable_methods(self) -> list[str]:
        """Declared methods that actually honor `--prefix` (never the PM methods).

        A custom-prefix or prefix-detected scenario must pin one of these:
        `package`/`upstream-package` install to a PM-managed location and
        silently ignore `--prefix`, so a scenario left on `auto` that resolves
        to a PM method would assert paths under the custom prefix that were
        never used. Narrowed by `prefix.applies_when` when declared, otherwise
        all declared non-PM methods. May be empty (a PM-only feature), in which
        case the caller skips the scenario entirely.
        """
        pm = {"package", "upstream-package"}
        applies = self.prefix_compatible_methods
        source = applies if applies is not None else self.method_names
        return [m for m in source if m not in pm]

    def resolved_bin_path(self, prefix: str, bin_name: str) -> str:
        """Full binary path under a given prefix: `{prefix}/{bin_dir}/{bin_name}`."""
        return f"{prefix}/{self.bin_dir}/{bin_name}"

    @property
    def is_git_clone_only(self) -> bool:
        """Whether this feature has no bins and declares a git-clone method.

        When true, the generic PATH/binary existence model doesn't apply —
        rules fall back to directory/git-config-based checks instead.
        """
        return not self.bins and "git-clone" in self.methods

    def git_clone_config(self) -> dict[str, str]:
        """`_options.method.git-clone.config`, with `{feat.version}` resolved.

        Resolved to `_options.version.default` — the version a `default`
        scenario install actually resolves to.
        """
        config = self.methods.get("git-clone", {}).get("config", {})
        default_version = self.version.get("default", "")
        return {
            key: str(value).replace("{feat.version}", default_version)
            for key, value in config.items()
        }

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

    def build_packages(self, method: str, pm: str) -> list[str]:
        """OS build-dep package names for `method` on package manager `pm`.

        Reads `_dependencies.build.{base,method-<method>}` in either declared
        shape: PM-keyed (`build.<group>.<pm>.packages`) or a run-deps-style
        package list (`build.<group>.packages` of bare names or `{name, <pm>:
        ...}` per-PM overrides). These are the packages the framework installs
        as root before a source/compile build; a non-root install can't install
        them itself, so a custom-prefix nonroot scenario must pre-install them.
        """
        build = self.dependencies.get("build", {})
        names: list[str] = []
        for group in ("base", f"method-{method}"):
            section = build.get(group)
            if not isinstance(section, dict):
                continue
            if "packages" in section:  # run-deps-style list
                names.extend(
                    spec if isinstance(spec, str) else spec.get(pm, spec.get("name"))
                    for spec in section["packages"]
                )
            elif isinstance(section.get(pm), dict):  # PM-keyed
                names.extend(section[pm].get("packages", []))
        return [n for n in names if n]


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
