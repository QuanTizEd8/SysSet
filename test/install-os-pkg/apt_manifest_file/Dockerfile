FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN mkdir -p /tmp \
 && printf '%s\n' \
      '# packages from implicit leading pkg block' \
      'packages:' \
      '  - tree' \
      '  - curl' \
      > /tmp/manifest.yaml
