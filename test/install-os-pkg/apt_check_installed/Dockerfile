FROM debian:latest
RUN apt-get update \
 && printf '#!/bin/sh\necho mytool-ok\n' > /usr/local/bin/mytool \
 && chmod +x /usr/local/bin/mytool \
 && printf 'mytool\ntree\n' > /tmp/manifest.txt
