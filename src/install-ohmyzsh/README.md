
# Oh My Zsh Installation (install-ohmyzsh)

Install Oh My Zsh in the development container.

## Example Usage

```json
"features": {
    "ghcr.io/QuanTizEd8/SysSet/install-ohmyzsh:0": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| configure_zshrc_for | Comma-separated list of usernames whose `~/.zshrc` should be configured to source Oh My Zsh.
For each user a guarded block is written (or replaced) between `# BEGIN install-ohmyzsh` and `# END install-ohmyzsh` markers.
Use `root` to configure the root user.
 | string | - |
| debug | Enable debug output. | boolean | false |
| font_dir | Path to the directory where fonts will be downloaded. | string | /usr/share/fonts/MesloLGS |
| install_dir | Path to the Oh My Zsh installation directory.
This is the directory where Oh My Zsh will be installed.
It corresponds to the [`ZSH`](https://github.com/ohmyzsh/ohmyzsh/wiki/Settings#zsh)
configuration variable in Oh My Zsh.
 | string | /usr/local/share/oh-my-zsh |
| install_fonts | Download and install the MesloLGS Nerd Font files to `font_dir` and refresh the font cache. | boolean | true |
| logfile | Log all output (stdout + stderr) to this file in addition to console. | string | - |
| plugins | Comma-separated list of Oh My Zsh custom plugins to install, each as a `owner/repo` GitHub slug.
The repository is cloned into `<zsh_custom_dir>/plugins/<repo>`.
Set to an empty string to install no custom plugins.
 | string | zsh-users/zsh-syntax-highlighting |
| theme | Oh My Zsh custom theme to install, as a `owner/repo` GitHub slug.
The repository is cloned into `<zsh_custom_dir>/themes/<repo>`.
Set to an empty string to install no custom theme.
 | string | romkatv/powerlevel10k |
| zsh_custom_dir | Path to the Oh My Zsh custom directory.
This corresponds to the [`ZSH_CUSTOM`](https://github.com/ohmyzsh/ohmyzsh/wiki/Settings#zsh_custom)
configuration variable in Oh My Zsh.
Defaults to `<install_dir>/custom`.
 | string | - |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/QuanTizEd8/SysSet/blob/main/src/install-ohmyzsh/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
