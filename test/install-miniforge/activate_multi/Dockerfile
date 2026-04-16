FROM ubuntu:latest
# Pre-install zsh so that 'conda init zsh' can write the zsh rc snippet
# and shell__detect_zshdir can probe the compiled-in zshenv path.
RUN apt-get update \
 && apt-get install -y --no-install-recommends zsh \
 && apt-get clean \
 && apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*
