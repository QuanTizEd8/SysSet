FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' \
      'prescripts:' \
      '  - mkdir -p /tmp/markers && touch /tmp/markers/prescript-ran' \
      'packages:' \
      '  - tree' \
      'scripts:' \
      '  - mkdir -p /tmp/markers && touch /tmp/markers/script-ran' \
      > /tmp/manifest.yaml
