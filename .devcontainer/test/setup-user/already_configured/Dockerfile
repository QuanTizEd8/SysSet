FROM ubuntu:latest
# Pre-create vscode user correctly so the feature can verify it without re-creating it.
RUN groupadd --gid 1000 vscode && \
    useradd --uid 1000 --gid 1000 \
            --home-dir /home/vscode --no-create-home \
            --shell /bin/bash vscode && \
    mkdir -p /home/vscode && \
    chown vscode:vscode /home/vscode
