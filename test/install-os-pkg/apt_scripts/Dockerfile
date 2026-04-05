FROM debian:latest
RUN mkdir -p /tmp/test-data \
 && echo "tree" > /tmp/test-data/apt-pkg \
 && printf '#!/bin/sh\nmkdir -p /tmp/markers && touch /tmp/markers/prescript-ran\n' \
      > /tmp/test-data/apt-prescript \
 && printf '#!/bin/sh\nmkdir -p /tmp/markers && touch /tmp/markers/script-ran\n' \
      > /tmp/test-data/apt-script \
 && chmod +x /tmp/test-data/apt-prescript /tmp/test-data/apt-script
