#!/bin/bash
# install_headless.sh — Hipfire Builder for GFX1030 (Headless)
# Builds the entire project (Engine + Quantizer + Tools) without GPU hardware.
set -euo pipefail

HIPFIRE_DIR="$HOME/.hipfire"
BIN_DIR="$HIPFIRE_DIR/bin"
MODELS_DIR="$HIPFIRE_DIR/models"
SRC_DIR="$HIPFIRE_DIR/src"
GITHUB_REPO="Kaden-Schutt/hipfire"
GITHUB_BRANCH="master"

# ─── HARDCODED CONFIG ───────────────────────────────────────
TARGET_ARCH="gfx1030"
# ───────────────────────────────────────────────────────────

echo "=== Hipfire Headless Builder (GFX1030) ==="
echo "Target Arch: $TARGET_ARCH"

# ─── Install Basics ─────────────────────────────────────────
if ! command -v unzip &>/dev/null; then
    apt-get update && apt-get install -y unzip || true
fi

if ! command -v bun &>/dev/null; then
    echo "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    export PATH="$BUN_INSTALL/bin:$PATH"
fi

# ─── Clone Repository ───────────────────────────────────────
mkdir -p "$HIPFIRE_DIR"
if [ ! -d "$SRC_DIR/.git" ]; then
    echo "Cloning repository..."
    git clone --depth 1 --branch "$GITHUB_BRANCH" "https://github.com/$GITHUB_REPO.git" "$SRC_DIR"
fi
REPO_DIR="$SRC_DIR"

# ─── Build Everything ───────────────────────────────────────
echo ""
echo "Starting Full Build (This may take a few minutes)..."

# 1. Setup Rust if missing
if ! command -v cargo &>/dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null
    . "$HOME/.cargo/env"
fi

# 2. Set Build Flags
export HSA_OVERRIDE_GFX_VERSION=10.3.0

# 3. Build the workspace
# We build the engine with features, and the quantizer explicitly.
cd "$REPO_DIR"

echo "Building Engine (Daemon + Infer)..."
cargo build --release --features deltanet --example daemon --example infer --example infer_hfq -p engine

echo "Building Quantizer and Tools..."
cargo build --release -p hipfire-quantize

# ─── Install Binaries (Auto-Detect) ─────────────────────────
echo ""
echo "Installing binaries to $BIN_DIR..."
mkdir -p "$BIN_DIR"

# Find and copy all built binaries (daemon, infer, quantizer, etc)
# 1. Copy binaries from target/release (this catches 'hipfire-quantize')
find target/release -maxdepth 1 -type f -executable -exec cp -f {} "$BIN_DIR/" \;

# 2. Copy binaries from target/release/examples (this catches 'daemon', 'infer')
if [ -d "target/release/examples" ]; then
    find target/release/examples -maxdepth 1 -type f -executable -exec cp -f {} "$BIN_DIR/" \;
fi

echo "  Binaries installed."
ls -la "$BIN_DIR"

# ─── Install CLI ────────────────────────────────────────────
mkdir -p "$HIPFIRE_DIR/cli"
cp cli/registry.json "$HIPFIRE_DIR/cli/"
cp cli/package.json  "$HIPFIRE_DIR/cli/"
cp cli/index.ts      "$HIPFIRE_DIR/cli/"

# Create wrapper
cat > "$BIN_DIR/hipfire" << 'WRAPPER'
#!/bin/bash
set -e
if command -v bun >/dev/null 2>&1; then BUN=bun;
elif [ -x "$HOME/.bun/bin/bun" ]; then BUN="$HOME/.bun/bin/bun";
else echo "Error: bun not found." >&2; exit 1; fi
exec "$BUN" run "$HOME/.hipfire/cli/index.ts" "$@"
WRAPPER
chmod +x "$BIN_DIR/hipfire"
echo "  CLI installed."

# ─── Install Kernels ────────────────────────────────────────
echo ""
echo "Setting up kernels for $TARGET_ARCH..."
KERNEL_DEST="$BIN_DIR/kernels/compiled/$TARGET_ARCH"
mkdir -p "$KERNEL_DEST"
if [ -d "kernels/compiled/$TARGET_ARCH" ]; then
    cp kernels/compiled/$TARGET_ARCH/*.hsaco "$KERNEL_DEST/" 2>/dev/null || true
    echo "  Kernels copied."
else
    echo "  No pre-compiled kernels found in repo. (Will JIT compile on first run)"
fi

# ─── Config ─────────────────────────────────────────────────
CONFIG="$HIPFIRE_DIR/config.json"
if [ ! -f "$CONFIG" ]; then
    cat > "$CONFIG" << CONF
{
  "temperature": 0.3,
  "top_p": 0.8,
  "max_tokens": 512,
  "gpu_arch": "$TARGET_ARCH"
}
CONF
fi

echo ""
echo "=== Install Complete ==="