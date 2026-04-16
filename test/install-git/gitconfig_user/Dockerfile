FROM ubuntu:24.04
# Pre-create the "vscode" user so the feature can write per-user gitconfig
# when add_remote_user_config=true and remoteUser="vscode".
RUN useradd -m -s /bin/bash vscode
