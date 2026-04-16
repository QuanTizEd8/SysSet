FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN apt-get update \
 && printf '#!/bin/sh\necho mytool-ok\n' > /usr/local/bin/mytool \
 && chmod +x /usr/local/bin/mytool \
 && printf '%s\n' 'packages:' '  - mytool' '  - tree' > /tmp/manifest.yaml
