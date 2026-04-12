# Manifest contains only an APK pkg section.
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
# On Debian (APT), the section selector [pm=apk] filters it out.
# The feature should detect no matching packages and exit cleanly.
FROM debian:latest
RUN printf '%s\n' 'apk:' '  packages:' '    - tree' > /tmp/manifest.yaml
