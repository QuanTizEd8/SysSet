FROM ubuntu:latest
# Pre-create "testuser" so the feature can add it to the nvm group and
# write per-user nvm RC files when add_users="testuser".
RUN useradd -m -s /bin/bash -u 1001 testuser
