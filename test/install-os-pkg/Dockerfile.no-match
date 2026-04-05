# Debian uses APT, but this directory only contains an APK package file.
# The feature should detect APT, find no apt-* files, and exit cleanly.
FROM debian:latest
RUN mkdir -p /tmp/test-data \
 && echo "tree" > /tmp/test-data/apk-pkg
