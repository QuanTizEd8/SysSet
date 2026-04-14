FROM ubuntu:latest
# Pre-create the "vscode" user so the feature can apply per-user configuration
# (git_protocol, setup_git, sign_commits) when add_remote_user_config=true and
# remoteUser="vscode".
RUN (apt-get update || (sleep 15 && apt-get update)) \
 && apt-get install -y --no-install-recommends git sudo \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash -u 1000 vscode \
 && echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode
