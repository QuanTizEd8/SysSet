FROM ubuntu:latest
# Pre-install gh 2.67.0 so version-match idempotency can be tested.
# The feature is called with version=2.67.0 + if_exists=fail; the version-match
# guard should exit 0 before if_exists policy is applied.
RUN apt-get update \
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
