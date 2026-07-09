"""Pure extraction of test-generation-relevant facts from a feature's metadata.yaml.

Deliberately does no rule logic — only answers "what does this feature's
metadata declare". Keeping extraction and generation strictly separate means a
new rule family only needs a new `FeatureFacts` field when it reads a metadata
shape no existing rule already reads; it never needs to touch how any other
rule works.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from proman import when_util


def _when_applies_to_pm(when: dict | list | None, pm: str) -> bool:
    """Whether a package entry's `when` applies to package manager `pm`.

    A `None`/absent `when` applies to every PM. Otherwise each clause's
    `plat.pm` (string or list) is checked; a clause with no `plat.pm`
    constraint applies to all PMs. Only `plat.pm` is considered — resolving a
    package *name* for a probe needs the PM discriminator, not the full
    os.id/version gating.
    """
    if when is None:
        return True
    for clause in when if isinstance(when, list) else [when]:
        pms = clause.get("plat.pm")
        if pms is None or pm == pms or (isinstance(pms, list) and pm in pms):
            return True
    return False


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
    def install_env(self) -> str | None:
        """`_options.verify.install_env`: env override for install-expecting scenarios.

        For a feature whose primary binary is pre-installed on the standard test
        envs (e.g. bash — Essential on every pool distro), install scenarios
        (default/method/version/prefix) skip there and never exercise a real
        install. Such features name a clean env where the tool is absent so the
        generator installs it for real (bash: a bash-less Alpine build env).
        """
        return self.verify.get("install_env")

    @property
    def install_env_nonroot(self) -> str | None:
        """`_options.verify.install_env_nonroot`: non-root variant of install_env."""
        return self.verify.get("install_env_nonroot")

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
    def exports_skipped(self) -> bool:
        """Whether `_options.prefix.exports.skip` suppresses the PATH-export block.

        With both symlink and export skipped, a prefix install lands its binary
        somewhere off the default PATH; the tool becomes reachable only via a
        login/interactive shell (the feature's discovery snippet or activation
        block written to profile.d / rc files). Generated checks must then assert
        the binary by absolute path plus a login-shell reachability probe rather
        than a bare `command -v` (which runs in the non-login test shell).
        """
        return bool(self.prefix.get("exports", {}).get("skip", False))

    @property
    def has_discovery_snippet(self) -> bool:
        """Whether `_options.prefix.discovery_snippet` provides per-shell PATH init.

        A feature (e.g. install-homebrew) can supply its own shell snippet
        (`eval "$(brew shellenv)"`) that the framework writes into profile.d and
        the shell rc files instead of a plain PATH export — making the tool
        available in login shells even when symlink+export are skipped.
        """
        return bool(self.prefix.get("discovery_snippet"))

    @property
    def activation_shells(self) -> list[str]:
        """`_options.prefix.activation.shells`, or `[]` when no activation block.

        An activation block (e.g. install-miniforge's `conda init <shell>`) is
        written to the named shells' rc files, putting the tool on PATH in
        interactive/login shells without a symlink or a plain PATH export.
        """
        return list(self.prefix.get("activation", {}).get("shells", ()))

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

    @property
    def download_methods(self) -> list[str]:
        """Declared methods that fetch assets into `installer_dir` (archive/asset/…).

        `binary`/`source`/`script` all go through `uri__fetch_asset`, which
        persists the downloaded archive (and its sidecar) under `--installer-dir`;
        `package`/`upstream-package`/`npm`/`cargo`/`git-clone` do not. Used by the
        `installer_dir` family to pick a method whose install actually populates
        the trace directory.
        """
        fetchers = {"binary", "source", "script"}
        return [m for m in self.method_names if m in fetchers]

    @property
    def has_sidecar(self) -> bool:
        """Whether any download method declares a checksum sidecar (`sidecar_uri`).

        Determines whether `installer_dir/sidecar/` is populated: features whose
        upstream ships a checksums file declare `sidecar_uri` (gh, just, pixi);
        those without (shellcheck) leave `sidecar/` empty, so asserting it would
        be a false failure.
        """
        return any(
            isinstance(cfg, dict) and cfg.get("sidecar_uri")
            for cfg in self.methods.values()
        )

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

    def package_name(self, method: str, pm: str | None = None) -> str:
        """Return the declared OS package name for a package-based method.

        `method` is "package" or "upstream-package"; names come from
        `_dependencies.run.method-<method>`. With `pm`, resolves the package
        entry whose `when` applies to that package manager and returns its
        per-PM name override (e.g. `apk: oras-cli`) else its `name` — package
        names legitimately differ across PMs (oras is `golang-oras` on dnf,
        `oras-cli` on apk, `oras` on apt). Without `pm`, returns the first
        declared name. Falls back to `primary_bin` when nothing is declared.
        """
        run_deps = self.dependencies.get("run", {})
        packages = run_deps.get(f"method-{method}", {}).get("packages", [])
        if pm is not None:
            for pkg in packages:
                if isinstance(pkg, dict) and _when_applies_to_pm(pkg.get("when"), pm):
                    return pkg.get(pm) or pkg.get("name") or self.primary_bin
        for pkg in packages:
            if isinstance(pkg, dict) and pkg.get("name"):
                return pkg["name"]
        return self.primary_bin

    def build_packages(
        self, method: str, pm: str, attrs: dict | None = None
    ) -> list[str]:
        """OS build-dep package names for `method` on package manager `pm`.

        Reads `_dependencies.build.{base,method-<method>}` in either declared
        shape: PM-keyed (`build.<group>.<pm>.packages`) or a run-deps-style
        package list (`build.<group>.packages` of bare names or `{name, <pm>:
        ..., when: ...}` per-PM/conditional entries). These are the packages the
        framework installs as root before a source/compile build; a non-root
        install can't install them itself, so a custom-prefix nonroot scenario
        must pre-install them.

        When `attrs` (an env's flattened attributes) is given, conditional
        (`when:`) package entries are filtered to those satisfied by that env —
        e.g. install-git's libpcre2-posix3/2/0 are gated on os.version_codename,
        so pre-installing all three would fail (only one exists per release).
        A `when:` that references only `feat.*` (e.g. the version-gated cargo/
        rust dep) can't be evaluated against an env, so it is kept: an extra
        pre-installed build dep is harmless, an omitted one breaks the build.
        """
        build = self.dependencies.get("build", {})
        names: list[str] = []
        for group in ("base", f"method-{method}"):
            section = build.get(group)
            if not isinstance(section, dict):
                continue
            if "packages" in section:  # run-deps-style list
                pkgs = section["packages"]
            elif isinstance(section.get(pm), dict):  # PM-keyed
                pkgs = section[pm].get("packages", [])
            else:
                continue
            for spec in pkgs:
                if isinstance(spec, str):
                    names.append(spec)
                elif attrs is None or self._build_pkg_applies(spec.get("when"), attrs):
                    names.append(spec.get(pm, spec.get("name")))
        return [n for n in names if n]

    @staticmethod
    def _build_pkg_applies(when: dict | list | None, attrs: dict) -> bool:
        """Whether a conditional build-dep entry applies to `attrs`.

        Only env-attribute conditions are evaluated; `feat.*` conditions (the
        install version, unknown at env-selection time) are dropped so a
        version-gated dep is always kept.
        """
        if not when:
            return True
        groups = when if isinstance(when, list) else [when]
        for group in groups:
            env_conds = {k: v for k, v in group.items() if not k.startswith("feat.")}
            if when_util.match(env_conds or None, attrs):
                return True
        return False


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
