FROM debian:latest
RUN apt-get update \
 && printf '%s\n' \
      'keys:' \
      '  - url: https://nginx.org/keys/nginx_signing.key' \
      '    dest: /usr/share/keyrings/nginx-archive-keyring.gpg' \
      'packages:' \
      '  - tree' \
      > /tmp/manifest.yaml
