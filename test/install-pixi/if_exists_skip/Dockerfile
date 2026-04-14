FROM ubuntu:latest
# Pre-install pixi (latest) so the if_exists_skip and if_exists_uninstall
# scenarios have an existing binary to detect.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && case "${ARCH}" in \
      x86_64)  TRIPLE="x86_64-unknown-linux-musl" ;; \
      aarch64) TRIPLE="aarch64-unknown-linux-musl" ;; \
      *)       TRIPLE="${ARCH}-unknown-linux-musl" ;; \
    esac \
 && curl --fail --location --retry 3 \
        "https://github.com/prefix-dev/pixi/releases/latest/download/pixi-${TRIPLE}.tar.gz" \
    | tar -xz -C /usr/local/bin \
 && chmod +x /usr/local/bin/pixi
ENV PATH="/usr/local/bin:${PATH}"
