FROM fedora:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' 'dnf:' '  packages:' '    - tree' > /tmp/manifest.yaml
