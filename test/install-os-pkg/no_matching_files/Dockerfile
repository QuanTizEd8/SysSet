# Manifest contains only an APK pkg section.
# On Debian (APT), the section selector [pm=apk] filters it out.
# The feature should detect no matching packages and exit cleanly.
FROM debian:latest
RUN printf '%s\n' '--- pkg [pm=apk]' 'tree' > /tmp/manifest.txt
