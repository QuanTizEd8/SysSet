FROM debian:latest
# Pre-create ZDOTDIR and a custom .zshrc so augment mode can be verified.
RUN mkdir -p /root/.config/zsh && \
    echo '# MY_CUSTOM_LINE' > /root/.config/zsh/.zshrc && \
    echo '# MY_CUSTOM_BASHRC' > /root/.bashrc
