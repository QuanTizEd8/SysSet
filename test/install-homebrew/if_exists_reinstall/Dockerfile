FROM ubuntu:latest
# Install Homebrew build dependencies, then install Homebrew as root.
# This simulates a prior run of install-homebrew so the if_exists=reinstall
# scenario can verify that the feature uninstalls the existing installation
# and reinstalls fresh, then runs post-install steps.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        git curl file build-essential procps ca-certificates \
 && apt-get clean \
 && apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*
RUN NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
