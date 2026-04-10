FROM ubuntu:latest
# Ubuntu ships an 'ubuntu' user at UID 1000; remove it first, then occupy the
# slot with old_user so the feature's replace_existing logic is exercised.
RUN userdel ubuntu 2>/dev/null || true && \
    groupdel ubuntu 2>/dev/null || true && \
    useradd --uid 1000 --user-group --no-create-home --shell /bin/sh old_user
