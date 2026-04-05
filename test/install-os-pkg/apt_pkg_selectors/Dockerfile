FROM debian:latest
RUN mkdir -p /tmp/test-data \
 && printf 'tree [pm=apt]\ncurl [pm=apt, id=debian]\nnot-a-real-package [pm=apk]\n' \
      > /tmp/test-data/apt-pkg
