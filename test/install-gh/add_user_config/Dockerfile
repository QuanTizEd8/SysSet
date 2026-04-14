FROM ubuntu:latest
# Pre-create "testuser" so the feature can apply per-user configuration
# (setup_git) when add_user_config="testuser" is the sole resolved user.
RUN (apt-get update || (sleep 15 && apt-get update)) \
 && apt-get install -y --no-install-recommends git sudo \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash -u 1001 testuser \
 && echo "testuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/testuser
