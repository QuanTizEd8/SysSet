FROM ubuntu:latest
# Pre-install Miniforge with conda 24.7.1 (tag 24.7.1-2) so the
# version_match_idempotency scenario can detect the existing installation,
# compare versions, and skip reinstall silently.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && curl --fail --location --retry 3 \
        --output /tmp/miniforge.sh \
        "https://github.com/conda-forge/miniforge/releases/download/24.7.1-2/Miniforge3-24.7.1-2-Linux-${ARCH}.sh" \
 && bash /tmp/miniforge.sh -b -p /opt/conda \
 && rm /tmp/miniforge.sh
ENV PATH="/opt/conda/bin:${PATH}"
