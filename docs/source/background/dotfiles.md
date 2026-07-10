# Dotfiles

Many applications allow users to customize their behavior through configuration files.
These are mostly plain text files that define user-specific settings and preferences
in a format recognized by the corresponding application (e.g., JSON, YAML, Bash).
They are commonly referred to as "dotfiles"
because their filenames usually begin with a dot (`.`).
This is Unix convention to hide files from default directory listings,
helping prevent accidental modifications or deletions.
This convention has persisted, and today "dotfiles" denotes configuration files
intended for system or application initialization rather than ordinary data or documents.

Applications expect their dotfiles in specific locations in the filesystem.
Some applications use hardcoded locations,
while others allow for customizing locations---usually
by setting environment variables
(cf. [XDG Base Directory Specification](https://wiki.archlinux.org/title/XDG_Base_Directory#Support)).
Usually, each configuration file has two variants:
a global configuration file located at a fixed (installation-specific) location and loaded for all users,
as well as a user-specific version stored in each user's home directory and loaded only for that user.
This allows setting global defaults for all users
while still allowing individual users to override and/or extend them.


## Dotfiles in Devcontainers

On a system shared by different users---such as a devcontainer---it
is good practice to prefer global dotfiles,
allowing each user to override and/or extend them using their own dotfiles.
A devcontainer commonly predefines a single non-root user for everyone using it,
so configuration placed directly and unconditionally in that user's home directory
risks overwriting changes the user makes later.
Keeping shared defaults in global files lets each user readily
[add their own dotfiles](https://code.visualstudio.com/docs/devcontainers/containers#_personalizing-with-dotfile-repositories)
in their home directory after connecting to the container,
without the risk of unintentionally overwriting global configurations.

## How DevFeats Manages Dotfiles

DevFeats features write **both** global dotfiles (system scope) and, when a feature configures
individual users (e.g. shell setup or `git` configuration), **per-user** dotfiles in each resolved
user's home directory — mirroring them into `/etc/skel` so newly created users inherit them too.

Writing into a user's home directory is made safe by **marker blocks**: each managed edit is
wrapped in delimited `# >>> <name> >>>` … `# <<< <name> <<<` markers, and only the content
*between* the markers is ever rewritten on re-runs. Anything you add outside the block is
preserved, so re-running a feature never clobbers your own customizations. See
{doc}`shell-config` and {doc}`env-vars` for the mechanism, and {doc}`/features/setup-shell/index` for
the feature that materializes the layered per-user shell configuration.
