FROM ubuntu:latest
# Pre-install gh (binary) so the if_exists scenarios have an existing binary to detect.
RUN (apt-get update || (sleep 15 && apt-get update)) \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && case "${ARCH}" in \
      x86_64)  ASSET_ARCH="amd64" ;; \
      aarch64) ASSET_ARCH="arm64" ;; \
      *)       ASSET_ARCH="amd64" ;; \
    esac \
 && GH_VERSION="2.67.0" \
 && curl --fail --silent --location --retry 3 \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ASSET_ARCH}.tar.gz" \
    | tar -xz -C /tmp \
 && install -m 755 "/tmp/gh_${GH_VERSION}_linux_${ASSET_ARCH}/bin/gh" /usr/local/bin/gh
