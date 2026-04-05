FROM alpine:latest
RUN apk add --no-cache bash \
 && mkdir -p /tmp \
 && printf '--- pkg [pm=apt]\nnot-a-real-package\n--- pkg [pm=apk]\ntree\n' \
      > /tmp/manifest.txt
