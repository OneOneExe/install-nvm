# ============================================================
# Dockerfile — installer-nvm
# Utility container: installs NVM in an isolated Ubuntu 24.04
# ============================================================

# --- Base image ---
FROM ubuntu:24.04

# --- Install runtime dependencies ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        sudo \
        curl \
        git \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# --- Copy project ---
WORKDIR /app
COPY . /app

# --- Make scripts executable ---
RUN chmod +x install-nvm.sh uninstall-nvm.sh lib/*.sh

# --- Run installer ---
CMD ["./install-nvm.sh", "--force"]
