FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN apt-get update \
 && printf '%s\n' \
      'keys:' \
      '  - url: https://nginx.org/keys/nginx_signing.key' \
      '    dest: /usr/share/keyrings/nginx-signing.key' \
      'packages:' \
      '  - tree' \
      > /tmp/manifest.yaml
