FROM ubuntu:latest
# Pre-install Miniforge with conda 24.7.1 (tag 24.7.1-2), run conda init bash
# to populate /root/.bashrc with the conda initialize block, and create a
# /root/.condarc.  The preserve_config_false scenario verifies that both are
# removed after an if_exists=uninstall cycle when preserve_config=false.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && curl --fail --location --retry 3 \
        --output /tmp/miniforge.sh \
        "https://github.com/conda-forge/miniforge/releases/download/24.7.1-2/Miniforge3-24.7.1-2-Linux-${ARCH}.sh" \
 && bash /tmp/miniforge.sh -b -p /opt/conda \
 && rm /tmp/miniforge.sh \
 && /opt/conda/bin/conda init bash \
 && echo "auto_activate_base: false" > /root/.condarc
ENV PATH="/opt/conda/bin:${PATH}"
