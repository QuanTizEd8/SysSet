FROM debian:latest
RUN printf '%s\n' \
      'packages:' \
      '  - name: tree' \
      '    when: "pm=apt"' \
      '  - name: curl' \
      '    when: "pm=apt and id=debian"' \
      '  - name: not-a-real-package' \
      '    when: "pm=apk"' \
      > /tmp/manifest.yaml
