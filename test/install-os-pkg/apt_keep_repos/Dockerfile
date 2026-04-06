FROM debian:latest
RUN apt-get update \
 && printf '%s\n' \
      '--- repo' \
      'deb http://deb.debian.org/debian stable main' \
      '--- pkg' \
      'tree' \
      > /tmp/manifest.txt
