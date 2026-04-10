FROM debian:latest
RUN mkdir -p /tmp \
 && printf '%s\n' '--- pkg [pm=apt]' 'tree' 'curl' '--- pkg [pm=apk]' 'not-a-real-package' \
      > /tmp/manifest.txt
