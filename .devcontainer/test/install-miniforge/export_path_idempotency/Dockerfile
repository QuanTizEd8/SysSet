FROM ubuntu:latest
# Simulate a prior install-miniforge run that wrote PATH blocks referencing
# /opt/conda/bin in all four Case-A targets.  The export_path_idempotency
# scenario then re-runs the feature with bin_dir=/opt/myforge (symlink=false),
# which must UPDATE the blocks in-place to /opt/myforge/bin without appending
# a second block (no duplicate markers).
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/*
RUN \
    # profile.d login-shell script \
    mkdir -p /etc/profile.d && \
    printf '# >>> conda PATH (install-miniforge) >>>\nexport PATH="/opt/conda/bin:${PATH}"\n# <<< conda PATH (install-miniforge) <<<\n' \
        >> /etc/profile.d/conda_bin_path.sh && \
    # global bashrc \
    printf '# >>> conda PATH (install-miniforge) >>>\nexport PATH="/opt/conda/bin:${PATH}"\n# <<< conda PATH (install-miniforge) <<<\n' \
        >> /etc/bash.bashrc && \
    # global zshenv \
    mkdir -p /etc/zsh && \
    printf '# >>> conda PATH (install-miniforge) >>>\nexport PATH="/opt/conda/bin:${PATH}"\n# <<< conda PATH (install-miniforge) <<<\n' \
        >> /etc/zsh/zshenv && \
    # bashenv (BASH_ENV target) + /etc/environment entry \
    printf '# >>> conda PATH (install-miniforge) >>>\nexport PATH="/opt/conda/bin:${PATH}"\n# <<< conda PATH (install-miniforge) <<<\n' \
        >> /etc/bashenv && \
    printf 'BASH_ENV="/etc/bashenv"\n' >> /etc/environment
