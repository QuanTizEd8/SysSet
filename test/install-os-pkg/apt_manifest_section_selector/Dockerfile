FROM debian:latest
RUN mkdir -p /tmp \
 && printf '--- pkg [pm=apt]\ntree\ncurl\n--- pkg [pm=apk]\nnot-a-real-package\n' \
      > /tmp/manifest.txt
