FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN apt-get update \
 && printf '%s\n' 'packages:' '  - tree' > /tmp/manifest.yaml
