FROM debian:latest
RUN mkdir -p /tmp \
 && printf '%s\n' \
      'prescripts:' \
      '  - touch /tmp/prescript-ran' \
      'packages:' \
      '  - tree' \
      'scripts:' \
      '  - touch /tmp/script-ran' \
      > /tmp/manifest.yaml
