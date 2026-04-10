FROM ubuntu:latest
RUN userdel ubuntu \
 && useradd -m -s /bin/bash devuser \
 && truncate -s 0 /etc/subuid /etc/subgid
