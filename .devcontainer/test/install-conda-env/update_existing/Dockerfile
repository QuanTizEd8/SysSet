FROM ubuntu:latest
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && curl --fail --location --retry 3 \
        --output /tmp/miniforge.sh \
        "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${ARCH}.sh" \
 && bash /tmp/miniforge.sh -b -p /opt/conda \
 && rm /tmp/miniforge.sh
ENV PATH="/opt/conda/bin:${PATH}"
RUN mkdir -p /tmp/test-envs \
 && printf 'name: simple\ndependencies:\n  - numpy\n' > /tmp/test-envs/simple.yml \
 && /opt/conda/bin/conda env create -f /tmp/test-envs/simple.yml \
 && printf 'name: simple\ndependencies:\n  - numpy\n  - pandas\n' > /tmp/test-envs/simple.yml
