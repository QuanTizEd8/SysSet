FROM ubuntu:24.04
# Pre-create the "vscode" user so the feature can write per-user gitconfig
# when users=_REMOTE_USER and remoteUser="vscode".
RUN useradd -m -s /bin/bash vscode
