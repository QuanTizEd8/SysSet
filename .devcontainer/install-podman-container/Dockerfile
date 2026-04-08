FROM ubuntu:latest

# Install Podman and rootless dependencies
RUN apt-get update && apt-get install -y \
        ca-certificates \
        podman \
        uidmap \
        fuse-overlayfs \
        slirp4netns \
        --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user to run Podman rootlessly
RUN useradd -m -s /bin/bash devuser

# Register UID/GID ranges for rootless user namespaces
RUN echo "devuser:100000:65536" >> /etc/subuid \
    && echo "devuser:100000:65536" >> /etc/subgid

# Configure Podman to use fuse-overlayfs (kernel overlay is blocked inside a container)
RUN mkdir -p /etc/containers \
    && printf '[storage]\ndriver = "overlay"\n\n[storage.options]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
       > /etc/containers/storage.conf

# Allow unqualified image names to resolve against Docker Hub
# (e.g. "openjournals/inara" instead of "docker.io/openjournals/inara")
RUN printf '[registries.search]\nregistries = ["docker.io"]\n' \
    >> /etc/containers/registries.conf
