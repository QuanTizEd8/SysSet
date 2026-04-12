FROM opensuse/leap:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' 'zypper:' '  packages:' '    - tree' > /tmp/manifest.yaml
