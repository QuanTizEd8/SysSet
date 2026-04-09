FROM condaforge/miniforge3
RUN mkdir -p /tmp/test-envs \
 && printf 'name: simple\ndependencies:\n  - numpy\n' > /tmp/test-envs/simple.yml \
 && /opt/conda/bin/conda env create -f /tmp/test-envs/simple.yml \
 && printf 'name: simple\ndependencies:\n  - numpy\n  - pandas\n' > /tmp/test-envs/simple.yml
