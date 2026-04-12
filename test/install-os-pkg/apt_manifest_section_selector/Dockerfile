FROM debian:latest
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
