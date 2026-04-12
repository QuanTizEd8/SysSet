FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN mkdir -p /tmp \
 && printf '%s\n' \
      'prescripts:' \
      '  - touch /tmp/prescript-ran' \
      'packages:' \
      '  - tree' \
      'scripts:' \
      '  - touch /tmp/script-ran' \
      > /tmp/manifest.yaml
