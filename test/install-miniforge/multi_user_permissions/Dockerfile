# Use Docker Hub ubuntu (same as most scenarios) — avoids flaky MCR pulls for
# mcr.microsoft.com/devcontainers/base:ubuntu in CI (see job logs: OCI blob fetch).
FROM ubuntu:latest

RUN useradd -m testuser1 && useradd -m testuser2
