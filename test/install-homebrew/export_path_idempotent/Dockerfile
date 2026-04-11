FROM ubuntu:latest
# Install Homebrew build dependencies, install Homebrew as the 'linuxbrew' user, then
# pre-write shellenv blocks into all three Case-A startup files.
# The export_path_idempotent scenario re-runs the feature with default
# options (if_exists=skip) and must UPDATE each block in-place without
# appending a duplicate.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        git curl file build-essential procps ca-certificates \
 && apt-get clean \
 && apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash linuxbrew
RUN runuser -u linuxbrew -- env NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Pre-write shellenv blocks — identical to what a first feature run writes.
# A second run (the scenario) must NOT add a second copy.
RUN \
    mkdir -p /etc/profile.d && \
    printf '# >>> brew shellenv (install-homebrew) >>>\neval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\n# <<< brew shellenv (install-homebrew) <<<\n' \
        >> /etc/profile.d/brew.sh && \
    printf '# >>> brew shellenv (install-homebrew) >>>\neval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\n# <<< brew shellenv (install-homebrew) <<<\n' \
        >> /etc/bash.bashrc && \
    mkdir -p /etc/zsh && \
    printf '# >>> brew shellenv (install-homebrew) >>>\neval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\n# <<< brew shellenv (install-homebrew) <<<\n' \
        >> /etc/zsh/zshenv
