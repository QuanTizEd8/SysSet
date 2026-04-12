FROM debian:latest
RUN mkdir -p /tmp \
 && printf '%s\n' \
      'prescripts:' \
      '  - echo pre >> /tmp/order.log' \
      'packages:' \
      '  - tree' \
      'scripts:' \
      '  - echo post >> /tmp/order.log' \
      > /tmp/manifest.yaml
