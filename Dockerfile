# syntax=docker/dockerfile:1

# ============================================================
# Dockerfile — install-nvm
#
# Utility container: installs NVM + Node.js LTS in an isolated
# Ubuntu 24.04 environment. Ephemeral (--rm), no host mounts.
#
# Build:
#   docker build -t installer-nvm:ubuntu-24.04 .
#
# Run:
#   docker run --rm installer-nvm:ubuntu-24.04
#   docker run --rm -it installer-nvm:ubuntu-24.04 bash
#
# Versions of NVM and Node.js are defined in config/nvm.conf —
# the single source of truth. They are NOT parameterized here.
#
# Docs:
#   README.md
#   MOTIVATION.md
# ============================================================

FROM ubuntu:24.04

# ============================================================
# Metadata (OCI)
# ============================================================
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="installer-nvm" \
      org.opencontainers.image.description="Utility container: installs NVM and Node.js LTS" \
      org.opencontainers.image.authors="Denis Roshchupkin" \
      org.opencontainers.image.source="https://github.com/OneOneExe/install-nvm" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# ============================================================
# Runtime environment
#
# DEBIAN_FRONTEND — silent apt during build.
# NVM_DIR        — NVM install location. For root: /root/.nvm.
#                  Matches config/nvm.conf default ($HOME/.nvm).
#                  Not added to PATH — nvm.sh sets it itself.
# ============================================================
ENV DEBIAN_FRONTEND=noninteractive \
    NVM_DIR=/root/.nvm

# ============================================================
# Project directory
# ============================================================
WORKDIR /app

# ============================================================
# System dependencies
#
# sudo — installer.sh uses `sudo apt install` for missing packages.
# curl — NVM installer download + internet check.
# git  — REQUIRED_PACKAGES in config/nvm.conf.
# ca-certificates — TLS for curl.
#
# One layer, cache cleaned in the same RUN.
# ============================================================
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        sudo \
        curl \
        git \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# ============================================================
# Project files
#
# Only what is needed at runtime.
# Excluded via .dockerignore: tests/, logs/, create-snapshot.sh,
# MOTIVATION.md, Dockerfile, .git, etc.
#
# --chmod=755 — entry points and modules must be executable.
# ============================================================
COPY --chmod=755 install-nvm.sh uninstall-nvm.sh /app/
COPY --chmod=755 lib/ /app/lib/
COPY config/ /app/config/
COPY README.md /app/

# ============================================================
# User
#
# Utility container: installs NVM system-wide inside the image.
# Root is intentional:
#   • NVM goes to /root/.nvm (matches $HOME/.nvm in config).
#   • installer.sh calls `sudo apt install` for dependencies.
#   • Ephemeral (--rm), nothing mounted from the host.
#   • No service, no network exposure, no long-lived process.
# ============================================================
USER root

# ============================================================
# Entry point
#
# ENTRYPOINT — fixed command (install-nvm.sh).
# CMD        — default arguments (--force).
#
#   docker run --rm installer-nvm:ubuntu-24.04
#     → ./install-nvm.sh --force
#
#   docker run --rm installer-nvm:ubuntu-24.04 --dry-run
#     → ./install-nvm.sh --dry-run
#
#   docker run --rm -it installer-nvm:ubuntu-24.04 bash
#     → bash (ENTRYPOINT overridden by shell command)
# ============================================================
ENTRYPOINT ["./install-nvm.sh"]
CMD ["--force"]