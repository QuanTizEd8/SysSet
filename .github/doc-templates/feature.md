# Feature Reference

<!-- Write a summary about the underlying tool that this feature installs or sets up, including what it does, its main use cases, and any important context or background information. -->

## Available Installation Methods

<!-- Write a summary of the feature's availability, installation/setup methods, and other key information for implementers, auditors, and maintainers. -->

<!-- Add one subsection for each available installation/setup method, using the template below -->

### <!-- Method Name (e.g. "OS Package Manager", "Binary Download", "Installer Script", "<Name of Tool> Installation") -->

#### Supported Platforms

<!-- List all supported platforms for this installation method, and any platform-specific notes or limitations, e.g.:
- macOS and all Linux distros
- Only Debian-based Linux distros (Ubuntu, Debian, etc.)
- Only Red Hat-based Linux distros (Fedora, CentOS, RHEL, etc.)
- Only macOS
- macOS and Linux distros with glibc 2.28+
- All Linux distros except those with musl libc (e.g. Alpine)
-->

#### Dependencies

- **Common Dependencies**: <!-- List all dependencies and requirements for this installation method that are common across all supported platforms, e.g. "Python 3.8+", "GCC 9+", "Docker", "Node.js 14+" -->
- **Platform-Specific Dependencies**: <!-- List any additional dependencies or requirements that are specific to certain platforms -->

#### Installation Steps

<!-- Write a detailed step-by-step description of the installation process for this method, including exact commands where possible. Mention any important considerations, such as required permissions (e.g. root/sudo), recommended installation paths, and any platform-specific steps or variations. -->

#### Installation Verification

<!-- Describe how to verify that the download/installation was successful, e.g. available checksums or signatures to download and verify, expected output of version or help commands, expected files or directories created, etc. -->

#### Configuration Options

- **Version Selection**: <!-- Describe how to select the version to install, e.g. by specifying a version number to the package manager, setting and environment variable, or by using a custom download URL. -->
- **Installation Path**: <!-- Describe how to specify the installation path, if applicable, and any important considerations for different platforms (e.g. default paths, recommended paths, permissions issues). -->
- **User Targeting**: <!-- Describe whether system-wide and/or user-local installation is supported, and how to specify the target (e.g. by running with or without sudo, by providing a `--user` flag, etc.). -->
- **Required Privileges**: <!-- Describe any required privileges for this installation method, such as whether it must be run as root or with sudo, and any important security considerations related to this. -->
- **Tool-Specific Configurations**: <!-- Describe all available configuration options for this installation method that are specific to the tool being installed, such as build options, tool-specific configuration files or persistent environment variables, etc., with details on how to set them (e.g. command-line flags, environment variables, configuration files). -->

#### Post-Installation Steps and Cleanup

- **PATH Setup**: <!-- Describe any necessary steps to add the installed tool to PATH, including platform-specific considerations (e.g. profile files to modify on Linux vs macOS, handling of Homebrew prefix on macOS, etc.) and user-targeting considerations (e.g. system-wide vs user-local installation). -->
- **Configuration Files**: <!-- Describe any configuration files that can be created or modified as part of the installation process, and what changes need to be made to them. -->
- **Environment Variables**: <!-- Describe any environment variables that need to be set persistently for the installed tool to work correctly. -->
- **Activation Scripts**: <!-- Describe any shell scripts that need to be sourced or activated for the installed tool to work correctly, and how to set that up. -->
- **Cleanup**: <!-- Describe any necessary cleanup steps, such as removing installation files, clearing caches, etc. -->


#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: <!-- Describe how to change to a different version of the installed tool, and any important considerations for this process (e.g. whether configuration files or environment variables need to be updated, whether the old version needs to be uninstalled first, etc.) -->
- **Uninstallation**: <!-- Describe how to uninstall the tool, and any important considerations for this process (e.g. whether it requires root/sudo, whether it leaves behind any configuration files or environment variables, etc.) -->
- **Idempotency**: <!-- Describe the behavior of the installation method if it is run multiple times, e.g. whether it will skip installation if the tool is already installed, whether it will overwrite the existing installation, etc. -->

#### Notes and Best Practices

<!-- Add any additional notes, tips, best practices, or important information related to this installation method that implementers, auditors, and maintainers should be aware of. This can include things like common pitfalls to avoid, security considerations, performance implications, compatibility issues, etc. -->

## References

<!-- Cite all references for the above information, including official documentation and source code, and other well-established resources. For each reference, provide a brief description of what it is and why it's relevant. For example: -->

- [Official Docs – Installation Methods](link)
- [Official Docs – Dependencies](link)
- [Official Github Repo – Configuration Options](link)
- [Installer Source Code – Post-Installation Steps](link)
- [Maintainer Blog Post – Installation Guide](link)
- [Similar Feature in Popular Project – <Issue> Handling](link)
