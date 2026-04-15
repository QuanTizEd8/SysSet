FROM ubuntu:latest
# Pre-create the "vscode" user so the feature can resolve it as the target
# for extension installation when add_remote_user_config=true and
# remoteUser="vscode".
RUN (apt-get update || (sleep 15 && apt-get update)) \
 && apt-get install -y --no-install-recommends git sudo \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash vscode \
 && echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode
