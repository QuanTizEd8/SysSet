FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN apt-get update \
 && printf '%s\n' \
      'repos:' \
      '  - "deb http://deb.debian.org/debian stable main"' \
      'packages:' \
      '  - tree' \
      > /tmp/manifest.yaml
