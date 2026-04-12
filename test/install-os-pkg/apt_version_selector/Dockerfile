FROM debian:bookworm
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' \
      'packages:' \
      '  - tree' \
      '  - name: bc' \
      '    when: "version_id=12"' \
      '  - name: less' \
      '    when: "id=debian and version_id=12"' \
      '  - name: mlocate' \
      '    when: "version_id=22.04"' \
      > /tmp/manifest.yaml
