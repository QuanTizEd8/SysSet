# Manifest file is empty — no packages are listed.
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
# The feature should detect no packages and exit cleanly without installing anything.
FROM debian:latest
RUN printf '' > /tmp/manifest.yaml
