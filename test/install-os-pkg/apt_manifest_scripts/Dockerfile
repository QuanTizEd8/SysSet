FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN mkdir -p /tmp \
 && printf '%s\n' \
      'prescripts:' \
      '  - echo pre >> /tmp/order.log' \
      'packages:' \
      '  - tree' \
      'scripts:' \
      '  - echo post >> /tmp/order.log' \
      > /tmp/manifest.yaml
