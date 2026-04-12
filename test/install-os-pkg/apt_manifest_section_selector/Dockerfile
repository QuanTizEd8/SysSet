FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN mkdir -p /tmp \
 && printf '%s\n' \
      'apt:' \
      '  packages:' \
      '    - tree' \
      '    - curl' \
      'apk:' \
      '  packages:' \
      '    - not-a-real-package' \
      > /tmp/manifest.yaml
