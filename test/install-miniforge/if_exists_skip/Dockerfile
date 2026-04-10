FROM ubuntu:latest
# Pre-install Miniforge at /opt/conda so the if_exists_skip scenario has an
# existing conda installation to detect and skip over.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && curl --fail --location --retry 3 \
        --output /tmp/miniforge.sh \
        "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${ARCH}.sh" \
 && bash /tmp/miniforge.sh -b -p /opt/conda \
 && rm /tmp/miniforge.sh
# Ensure conda is on PATH so the feature's 'command -v conda' check succeeds.
ENV PATH="/opt/conda/bin:${PATH}"
