FROM archlinux:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' 'pacman:' '  packages:' '    - tree' > /tmp/manifest.yaml
