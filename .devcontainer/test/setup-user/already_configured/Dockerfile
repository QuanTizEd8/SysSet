FROM ubuntu:latest
# Ubuntu ships an 'ubuntu' user/group at UID/GID 1000; evict them first, then
# pre-create vscode correctly so the feature recognises it and passes through.
RUN userdel ubuntu 2>/dev/null || true && \
    groupdel ubuntu 2>/dev/null || true && \
    groupadd --gid 1000 vscode && \
    useradd --uid 1000 --gid 1000 \
            --home-dir /home/vscode --no-create-home \
            --shell /bin/bash vscode && \
    mkdir -p /home/vscode && \
    chown vscode:vscode /home/vscode
