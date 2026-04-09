FROM condaforge/miniforge3
RUN mkdir -p /tmp/test-envs \
 && printf 'name: envA\ndependencies:\n  - numpy\n' > /tmp/test-envs/envA.yml \
 && printf 'name: envB\ndependencies:\n  - pandas\n' > /tmp/test-envs/envB.yml
