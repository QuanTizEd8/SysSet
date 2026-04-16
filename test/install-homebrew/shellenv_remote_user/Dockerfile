FROM ubuntu:latest
# Pre-create the "vscode" user so the feature can write per-user shellenv
# blocks when add_remote_user_config=true and remoteUser="vscode".
RUN useradd -m -s /bin/bash vscode
