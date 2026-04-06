
# OS Package Installer (install-os-pkg)

Install packages from the operating system's package manager.

## Example Usage

```json
"features": {
    "ghcr.io/QuanTizEd8/SysSet/install-os-pkg:0": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| debug | Enable debug output. | boolean | false |
| install_self | Install the 'install-os-pkg' system command.
When true (the default), a wrapper script is written to
/usr/local/bin/install-os-pkg so other features or scripts can invoke
the installer directly after this feature has run.
Set to false to skip this step.
 | boolean | true |
| interactive | Run in interactive mode.
By default, the installation runs non-interactively.
Set this flag to allow interactive prompts.
 | boolean | false |
| keep_repos | Keep added repositories after installation.
By default, any repository drop-in files written during installation
are removed after the script finishes.
Set this flag to keep them permanently.
 | boolean | false |
| lifecycle_hook | Defer package installation to a devcontainer lifecycle hook.
When set, the feature registers a hook script instead of installing
packages at build time. The script is called by the devcontainer CLI
at the specified lifecycle event.
Supported values: onCreate, updateContent, postCreate.
Leave empty (the default) to install packages immediately at build time.
 | string | - |
| logfile | Log all output (stdout + stderr) to this file in addition to console. | string | - |
| no_clean | Do not clean the package manager cache after installation.
By default, the package manager's cache is cleaned after installation.
This option skips that step.
 | boolean | false |
| manifest | Inline manifest content or path to a manifest file.
A manifest is a text document divided into sections by '--- type [selectors]'
headers. The implicit leading block (before any header) is treated as a 'pkg'
section. Supported section types: key, pkg, prescript, repo, script.
  key: one 'url dest-path' entry per line — fetches a signing key with curl;
       if dest-path ends in .gpg the key is dearmored via gpg --dearmor.
  prescript / script: shell commands run before / after package installation.
  repo: package-manager repo lines added before the install step.
  pkg: package names to install, one per line.
Optional selector blocks on a section header (or on individual package lines)
use the syntax '[key=val, key=val]' and are matched against /etc/os-release
fields plus the synthetic keys 'pm' (e.g. apt) and 'arch' (e.g. x86_64).
Multiple blocks on the same line are OR'd; conditions within a block are AND'd.
Inline content is detected when the value contains a newline; otherwise the
value is treated as a file path.
 | string | - |
| no_update | Do not update package lists before installation.
By default, package lists are refreshed before installing packages.
This option skips that step.
 | boolean | false |
| lists_max_age | Maximum age of package lists (in seconds) before an update is considered necessary.
When the package lists were refreshed more recently than this threshold the update
step is skipped automatically (unless a new repository was added by the manifest).
Set to 0 to always update. Has no effect when no_update is true.
 | string | 300 |
| dry_run | Print what would be installed/fetched without making any changes.
No packages are installed, no files are written, and no scripts are executed.
Root privilege is not required when this is set.
 | boolean | false |
| check_installed | Skip packages that are already available in PATH.
When true, each package name is checked with 'command -v' before installation.
Packages whose binary is already present in PATH are skipped regardless of
whether they were installed via the system package manager.
 | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/QuanTizEd8/SysSet/blob/main/src/install-os-pkg/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
