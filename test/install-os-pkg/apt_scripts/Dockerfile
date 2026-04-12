FROM debian:latest
RUN printf '%s\n' \
      'prescripts:' \
      '  - mkdir -p /tmp/markers && touch /tmp/markers/prescript-ran' \
      'packages:' \
      '  - tree' \
      'scripts:' \
      '  - mkdir -p /tmp/markers && touch /tmp/markers/script-ran' \
      > /tmp/manifest.yaml
