FROM debian:latest
RUN printf '%s\n' \
      '--- prescript' \
      'mkdir -p /tmp/markers && touch /tmp/markers/prescript-ran' \
      '--- pkg' \
      'tree' \
      '--- script' \
      'mkdir -p /tmp/markers && touch /tmp/markers/script-ran' \
      > /tmp/manifest.txt
