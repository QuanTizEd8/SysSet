FROM debian:latest
RUN apt-get update \
 && printf '%s\n' \
      'repos:' \
      '  - "deb http://deb.debian.org/debian stable main"' \
      'packages:' \
      '  - tree' \
      > /tmp/manifest.yaml
