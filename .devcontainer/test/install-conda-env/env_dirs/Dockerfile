FROM condaforge/miniforge3
RUN mkdir -p /tmp/test-envs \
 && printf 'name: direnv1\ndependencies:\n  - numpy\n' > /tmp/test-envs/direnv1.yml \
 && printf 'name: direnv2\ndependencies:\n  - pandas\n' > /tmp/test-envs/direnv2.yml
