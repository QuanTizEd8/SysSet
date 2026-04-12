FROM alpine:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN apk add --no-cache bash \
 && mkdir -p /tmp \
 && printf '%s\n' \
      'apt:' \
      '  packages:' \
      '    - not-a-real-package' \
      'apk:' \
      '  packages:' \
      '    - tree' \
      > /tmp/manifest.yaml
