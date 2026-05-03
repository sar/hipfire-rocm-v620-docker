FROM rocm/dev-ubuntu-24.04:7.2.1-complete

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    wget \
    unzip \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Set Environment Variables for Headless Build
ENV HSA_OVERRIDE_GFX_VERSION=10.3.0
ENV AMDGPU_TARGETS=gfx1030

WORKDIR /app

# 3. Copy the modified install script
COPY install_headless.sh /app/install_headless.sh
RUN chmod +x /app/install_headless.sh

# 4. Run the installer
# This will clone the repo, build the binaries, and place them in ~/.hipfire
RUN /app/install_headless.sh

# Set PATH so you can run 'hipfire' immediately
ENV PATH="/root/.hipfire/bin:${PATH}"

CMD ["/bin/bash"]