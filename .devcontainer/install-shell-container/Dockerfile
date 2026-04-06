FROM ubuntu:latest
ENV MY_DOCKER_VAR=hello
ENV MY_DOCKER_VAR2="hello world"
RUN apt-get update && apt-get install -y zsh git curl
# Create a file at /etc/environment.d/myenv.conf with some environment variables
RUN mkdir -p /etc/environment.d && \
    echo 'MY_ENVD_VAR=hello' > /etc/environment.d/myenv.conf