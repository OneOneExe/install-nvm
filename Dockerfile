# syntax=docker/dockerfile:1

# ============================================================
# installer-nvm — utility container
# Installs NVM and Node.js in an isolated Ubuntu 24.04
# ============================================================

# --- Base image ---
FROM ubuntu:24.04

# --- Metadata ---
LABEL org.opencontainers.image.title="installer-nvm"
LABEL org.opencontainers.image.description="Utility container: installs NVM and Node.js LTS in an isolated Ubuntu 24.04"
LABEL org.opencontainers.image.authors="Denis Roshchupkin"
LABEL org.opencontainers.image.source="https://github.com/OneOneExe/installer-nvm"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="1.0.0"

# --- Shell: use bash explicitly for predictable behavior ---
SHELL ["/bin/bash", "-c"]

# --- Runtime dependencies ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        sudo \
        curl \
        git \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# --- Project ---
WORKDIR /app
COPY . /app

# --- Make scripts executable ---
RUN chmod +x install-nvm.sh uninstall-nvm.sh lib/*.sh

# --- Run as root (intentional) ---
# This is a utility container: it installs NVM system-wide inside
# the isolated environment. The container is ephemeral (--rm) and
# does not mount anything from the host, so root is acceptable here.
# For service containers, use USER <non-root> instead.
USER root

# --- Default command ---
CMD ["./install-nvm.sh", "--force"]
