FROM ubuntu:latest
# Pre-install Miniforge with conda 24.7.1 (tag 24.7.1-2) and create a named
# environment "myenv" so the preserve_envs_false scenario can verify that the
# environment is removed after an if_exists=reinstall cycle when preserve_envs=false.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && curl --fail --location --retry 3 \
        --output /tmp/miniforge.sh \
        "https://github.com/conda-forge/miniforge/releases/download/24.7.1-2/Miniforge3-24.7.1-2-Linux-${ARCH}.sh" \
 && bash /tmp/miniforge.sh -b -p /opt/conda \
 && rm /tmp/miniforge.sh \
 && /opt/conda/bin/conda create -n myenv --yes
ENV PATH="/opt/conda/bin:${PATH}"
