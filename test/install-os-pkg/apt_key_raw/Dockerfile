FROM debian:latest
RUN apt-get update \
 && printf '%s\n' \
      '--- key' \
      'https://nginx.org/keys/nginx_signing.key /usr/share/keyrings/nginx-signing.key' \
      '--- pkg' \
      'tree' \
      > /tmp/manifest.txt
