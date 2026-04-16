FROM alpine:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN apk update \
 && printf '%s\n' 'apk:' '  packages:' '    - tree' > /tmp/manifest.yaml
