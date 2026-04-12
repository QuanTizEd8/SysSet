FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' \
      'packages:' \
      '  - name: tree' \
      '    when: "pm=apt"' \
      '  - name: curl' \
      '    when: "pm=apt and id=debian"' \
      '  - name: not-a-real-package' \
      '    when: "pm=apk"' \
      > /tmp/manifest.yaml
