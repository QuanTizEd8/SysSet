FROM ubuntu:24.04
# Pre-install git so the if_exists=skip feature path is exercised.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/*
