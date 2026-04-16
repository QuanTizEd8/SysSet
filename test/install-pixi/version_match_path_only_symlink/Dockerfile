FROM ubuntu:latest
# Pre-install pixi 0.41.0 only on PATH (/usr/bin), not at the feature's
# requested PREFIX, so the version-match shortcut must not treat the requested
# install target as already satisfied.
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
        "https://github.com/prefix-dev/pixi/releases/download/v0.41.0/pixi-${TRIPLE}.tar.gz" \
    | tar -xz -C /usr/bin \
 && chmod +x /usr/bin/pixi
ENV PATH="/usr/bin:${PATH}"