FROM ubuntu:latest
RUN userdel ubuntu \
 && useradd -m -s /bin/bash alice \
 && useradd -m -s /bin/bash bob \
 && truncate -s 0 /etc/subuid /etc/subgid
