FROM debian:latest
RUN mkdir -p /tmp \
 && printf '%s\n' \
      '# packages from implicit leading pkg block' \
      'packages:' \
      '  - tree' \
      '  - curl' \
      > /tmp/manifest.yaml
