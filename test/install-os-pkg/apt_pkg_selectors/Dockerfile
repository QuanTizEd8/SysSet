FROM debian:latest
RUN printf '%s\n' \
      'tree [pm=apt]' \
      'curl [pm=apt, id=debian]' \
      'not-a-real-package [pm=apk]' \
      > /tmp/manifest.txt
