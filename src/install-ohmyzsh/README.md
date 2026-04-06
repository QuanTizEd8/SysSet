
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
| debug | Enable debug output. | boolean | false |
| font_dir | Path to the directory where fonts will be downloaded. | string | /usr/share/fonts/MesloLGS |
| install_dir | Path to the Oh My Zsh installation directory.
This is the directory where Oh My Zsh will be installed.
It corresponds to the [`ZSH`](https://github.com/ohmyzsh/ohmyzsh/wiki/Settings#zsh_custom)
configuration variable in Oh My Zsh.
 | string | /usr/local/share/oh-my-zsh |
| logfile | Log all output (stdout + stderr) to this file in addition to console. | string | - |
| zsh_custom_dir | Path to the Oh My Zsh custom directory.
This corresponds to the [`ZSH_CUSTOM`](https://github.com/ohmyzsh/ohmyzsh/wiki/Settings#zsh_custom)
configuration variable in Oh My Zsh.
 | string | /usr/local/share/oh-my-zsh/custom |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/QuanTizEd8/SysSet/blob/main/src/install-ohmyzsh/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
