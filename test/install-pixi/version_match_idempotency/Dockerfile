FROM ubuntu:latest
# Pre-install pixi 0.41.0 so the version_match_idempotency scenario can verify
# that requesting the same version skips reinstall even when if_exists=reinstall.
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
    | tar -xz -C /usr/local/bin \
 && chmod +x /usr/local/bin/pixi
ENV PATH="/usr/local/bin:${PATH}"
