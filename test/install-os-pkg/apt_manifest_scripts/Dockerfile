FROM debian:latest
RUN mkdir -p /tmp \
 && printf '%s\n' \
      '--- prescript' \
      'echo pre >> /tmp/order.log' \
      '--- pkg' \
      'tree' \
      '--- script' \
      'echo post >> /tmp/order.log' \
      > /tmp/manifest.txt
