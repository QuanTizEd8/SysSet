FROM ubuntu:latest
RUN userdel ubuntu \
 && useradd -m -s /bin/bash vscode \
 && truncate -s 0 /etc/subuid /etc/subgid
