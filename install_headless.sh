#!/bin/bash
# install_headless.sh — Modified hipfire installer for GPU-less builds.
# Forces gfx1030 architecture.
set -euo pipefail

HIPFIRE_DIR="$HOME/.hipfire"
BIN_DIR="$HIPFIRE_DIR/bin"
MODELS_DIR="$HIPFIRE_DIR/models"
SRC_DIR="$HIPFIRE_DIR/src"
GITHUB_REPO="Kaden-Schutt/hipfire"
GITHUB_BRANCH="master"

# ─── HARDCODED CONFIG FOR HEADLESS BUILD ──────────────────
TARGET_ARCH="gfx1030"
# ───────────────────────────────────────────────────────────

echo "=== hipfire installer (HEADLESS MODE) ==="
echo ""

# ─── Interactive prompts ───────────────────────────────────
ask() {
    local prompt="$1" default="$2"
    if printf "%s" "$prompt" >/dev/tty 2>/dev/null; then
        local reply
        read -r reply </dev/tty 2>/dev/null || reply="$default"
        echo "${reply:-$default}"
    else
        echo "$default"
    fi
}

# ─── OS Detection ──────────────────────────────────────────
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
if [ "$OS" != "linux" ]; then
    echo "This modified script is for Linux only."
    exit 1
fi
echo "OS: $OS ($ARCH)"

# ─── GPU Detection (PATCHED) ───────────────────────────────
echo ""
echo "Checking for AMD GPU..."
if [ ! -e /dev/kfd ]; then
    echo "  /dev/kfd not found (Headless Mode)."
    echo "  Forcing GPU ARCH: $TARGET_ARCH"
    GPU_ARCH="$TARGET_ARCH"
else
    echo "  /dev/kfd: found ✓"
    # Standard detection logic...
    GPU_ARCH="unknown"
    for node_props in /sys/class/kfd/kfd/topology/nodes/*/properties; do
        [ -f "$node_props" ] || continue
        ver=$(grep -oP 'gfx_target_version\s+\K\d+' "$node_props" 2>/dev/null || true)
        case "$ver" in
            90006)          GPU_ARCH="gfx906";  break ;;
            90008)          GPU_ARCH="gfx908";  break ;;
            100100)         GPU_ARCH="gfx1010"; break ;;
            100300|100302)  GPU_ARCH="gfx1030"; break ;;
            110000|110001)  GPU_ARCH="gfx1100"; break ;;
        esac
    done
fi

if [ "$GPU_ARCH" = "unknown" ]; then
    GPU_ARCH="$TARGET_ARCH"
fi
echo "  Target Arch: $GPU_ARCH"

# ─── HIP Runtime ───────────────────────────────────────────
echo ""
echo "Checking HIP runtime..."
HIP_FOUND=false
# (Checks standard paths)
for dir in /opt/rocm/lib /opt/rocm/lib64 /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu; do
    for suffix in "" ".6" ".7" ".8"; do
        lib="$dir/libamdhip64.so${suffix}"
        if [ -f "$lib" ]; then
            echo "  libamdhip64.so: found at $lib ✓"
            HIP_FOUND=true
            break 2
        fi
    done
done

if ! $HIP_FOUND; then
    echo "  HIP Runtime not found. Please install rocm-hip-runtime."
    # In a container, this should already exist.
fi

# ─── Install Bun ───────────────────────────────────────────
echo ""
if command -v bun &>/dev/null; then
    echo "Bun: found ✓"
else
    echo "Installing Bun..."
    if ! command -v unzip &>/dev/null; then
        apt-get update && apt-get install -y unzip || true
    fi
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    export PATH="$BUN_INSTALL/bin:$PATH"
fi

# ─── Create directories ────────────────────────────────────
mkdir -p "$BIN_DIR" "$MODELS_DIR"

# ─── Determine install mode ────────────────────────────────
INSTALL_MODE="remote"
REPO_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null)" || true
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../Cargo.toml" ]; then
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    INSTALL_MODE="local"
fi

echo ""
if [ "$INSTALL_MODE" = "local" ]; then
    echo "Install mode: local"
else
    echo "Install mode: remote (cloning repository)"
    if [ ! -d "$SRC_DIR/.git" ]; then
        git clone --depth 1 --branch "$GITHUB_BRANCH" "https://github.com/$GITHUB_REPO.git" "$SRC_DIR"
    fi
    REPO_DIR="$SRC_DIR"
fi

# ─── Build / Install binaries ──────────────────────────────
echo ""
echo "Installing hipfire..."

if [ -f "$REPO_DIR/target/release/examples/daemon" ]; then
    echo "  Pre-built binaries found ✓"
else
    echo "  Building from source..."
    if ! command -v cargo &>/dev/null; then
        echo "  Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null
        . "$HOME/.cargo/env"
    fi
    
    # Export env vars for the compiler
    export HSA_OVERRIDE_GFX_VERSION=10.3.0
    
    (cd "$REPO_DIR" && \
        echo "  cargo build --release..." && \
        cargo build --release --features deltanet --example daemon --example infer --example infer_hfq -p engine 2>&1 | tail -5)
    
    if [ ! -f "$REPO_DIR/target/release/examples/daemon" ]; then
        echo "  BUILD FAILED."
        exit 1
    fi
    echo "  Build complete ✓"
fi

# Copy binaries
cp "$REPO_DIR/target/release/examples/daemon" "$BIN_DIR/daemon"
cp "$REPO_DIR/target/release/examples/infer" "$BIN_DIR/infer" 2>/dev/null || true
cp "$REPO_DIR/target/release/examples/infer_hfq" "$BIN_DIR/infer_hfq" 2>/dev/null || true

# Copy CLI
mkdir -p "$HIPFIRE_DIR/cli"
cp "$REPO_DIR/cli/registry.json" "$HIPFIRE_DIR/cli/registry.json"
cp "$REPO_DIR/cli/package.json"  "$HIPFIRE_DIR/cli/package.json"
cp "$REPO_DIR/cli/index.ts"      "$HIPFIRE_DIR/cli/index.ts"

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
echo "  Binaries + CLI installed ✓"

# ─── Install kernels (PATCHED) ─────────────────────────────
# We skip pre-compiling because we don't have a GPU.
echo ""
if [ "$GPU_ARCH" != "unknown" ]; then
    echo "Copying kernels for $GPU_ARCH..."
    KERNEL_DEST="$BIN_DIR/kernels/compiled/$GPU_ARCH"
    mkdir -p "$KERNEL_DEST"
    if [ -d "$REPO_DIR/kernels/compiled/$GPU_ARCH" ]; then
        cp "$REPO_DIR/kernels/compiled/$GPU_ARCH"/*.hsaco "$KERNEL_DEST/" 2>/dev/null || true
        echo "  Kernels copied."
    else
        echo "  No pre-built kernels in repo. Kernels will compile on first run."
    fi
fi

# ─── Config ────────────────────────────────────────────────
CONFIG="$HIPFIRE_DIR/config.json"
if [ ! -f "$CONFIG" ]; then
    cat > "$CONFIG" << CONF
{
  "temperature": 0.3,
  "top_p": 0.8,
  "max_tokens": 512,
  "gpu_arch": "$GPU_ARCH"
}
CONF
fi

echo ""
echo "=== hipfire installed ==="