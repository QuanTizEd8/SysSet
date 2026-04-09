FROM ubuntu:latest
# Pre-create a user that occupies UID 1000 — the feature should evict it.
RUN useradd --uid 1000 --user-group --no-create-home --shell /bin/sh old_user
