#!/bin/bash
# deps.sh — Sets up build environment for hipfire on Ubuntu 24.04 (Headless/GPU-less)

set -e

echo "=== Installing Build Dependencies (Ubuntu 24.04) ==="

# 1. System basics
sudo apt-get update
sudo apt-get install -y build-essential curl git wget pkg-config unzip libssl-dev

# 2. Install Rust (if missing)
if ! command -v cargo &>/dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # Source Rust for the current session
    . "$HOME/.cargo/env"
else
    echo "Rust already installed."
fi

# 3. Install Bun (required for hipfire CLI)
if ! command -v bun &>/dev/null; then
    echo "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
else
    echo "Bun already installed."
fi

# 4. Install ROCm SDK (Headless)
# We install the development libraries and runtime, but explicitly skip the kernel driver (DKMS)
# since there is no GPU attached.
echo "Setting up ROCm Repository..."
# Download the amdgpu-install package for Ubuntu (noble = 24.04)
wget -q https://repo.radeon.com/amdgpu-install/6.2/ubuntu/noble/amdgpu-install_6.2.60200-1_all.deb -O /tmp/amdgpu-install.deb
sudo apt-get install -y /tmp/amdgpu-install.deb

echo "Installing ROCm Libraries (No Driver)..."
# --usecase=rocm,hip,hipsdk installs the compiler and libs.
# --no-dkms prevents trying to build the kernel module (which fails without GPU).
sudo amdgpu-install --accept-eula --usecase=rocm,hip,hipsdk --no-dkms -y

echo ""
echo "=== Dependencies Installed ==="
echo "NOTE: You may need to restart your shell or run: source \$HOME/.cargo/env"