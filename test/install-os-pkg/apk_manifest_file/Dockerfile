FROM alpine:latest
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
