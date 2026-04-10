FROM debian:latest
RUN mkdir -p /tmp \
 && printf '%s\n' \
      '--- prescript' \
      'touch /tmp/prescript-ran' \
      '--- pkg' \
      'tree' \
      '--- script' \
      'touch /tmp/script-ran' \
      > /tmp/manifest.txt
