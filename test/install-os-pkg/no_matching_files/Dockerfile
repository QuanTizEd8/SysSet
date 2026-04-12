# Manifest contains only an APK pkg section.
ARG GITHUB_TOKEN
# On Debian (APT), the apk: block is filtered out.
# The feature should detect no matching packages and exit cleanly.
FROM debian:latest
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' 'apk:' '  packages:' '    - tree' > /tmp/manifest.yaml
