#!/bin/bash
# setup-linux.sh
# One-time Linux dev-environment provisioner (setup-dev.ps1 equivalent).
# Usage: ./setup-linux.sh [DEV_ROOT] [--skip-apt]
#
# Installs system packages (unless --skip-apt), verifies the Swift toolchain,
# and builds SDL3 / SDL3_image / SDL3_ttf / zlib-ng plus PDFium and DXC into
# DEV_ROOT (default: $HOME/dev) in the layout compile-linux.sh expects.
# Dependency versions can be overridden via SDL3_VERSION etc. environment vars.
set -e

SDL3_VERSION="${SDL3_VERSION:-3.4.18}"
SDL3_IMAGE_VERSION="${SDL3_IMAGE_VERSION:-3.4.8}"
SDL3_TTF_VERSION="${SDL3_TTF_VERSION:-3.2.2}"
ZLIB_NG_VERSION="${ZLIB_NG_VERSION:-2.3.3}"
PDFIUM_TAG="${PDFIUM_TAG:-chromium%2F7891}"
DXC_VERSION="${DXC_VERSION:-v1.8.2407}"
DXC_ASSET="${DXC_ASSET:-linux_dxc_2024_07_31.x86_64.tar.gz}"

DEV_ROOT="$HOME/dev"
SKIP_APT=0
for arg in "$@"; do
    case "$arg" in
        --skip-apt) SKIP_APT=1 ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) DEV_ROOT="$arg" ;;
    esac
done

ARCH="$(uname -m)"
PDFIUM_ASSET="pdfium-linux-x64.tgz"
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    PDFIUM_ASSET="pdfium-linux-arm64.tgz"
fi

echo "### Provisioning Linux dev environment in $DEV_ROOT ($ARCH) ###"
mkdir -p "$DEV_ROOT"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# ------------------------------------------------------------------
# 1. System packages
# ------------------------------------------------------------------
if [ "$SKIP_APT" -eq 0 ]; then
    sudo apt-get update
    sudo apt-get install -y \
        build-essential git cmake ninja-build pkg-config curl \
        glslang-tools spirv-tools \
        libasound2-dev libpulse-dev libaudio-dev libjack-dev libsndio-dev \
        libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
        libxi-dev libxss-dev libxtst-dev libxkbcommon-dev \
        libdrm-dev libgbm-dev libgl1-mesa-dev libgles2-mesa-dev \
        libegl1-mesa-dev libdbus-1-dev libibus-1.0-dev libthai-dev \
        libudev-dev libusb-1.0-0-dev libfribidi-dev \
        libpipewire-0.3-dev libwayland-dev wayland-protocols \
        libdecor-0-dev liburing-dev \
        libvulkan-dev \
        libpng-dev libjpeg-dev libwebp-dev libtiff-dev \
        libfreetype-dev libharfbuzz-dev
else
    echo "(skipping apt; expecting toolchain and libraries to be present)"
fi

# ------------------------------------------------------------------
# 2. Toolchain checks
# ------------------------------------------------------------------
command -v swift >/dev/null 2>&1 || {
    echo "swift not found on PATH. Install it via Swiftly first:" >&2
    echo "  https://www.swift.org/install/linux/" >&2
    exit 1
}
echo "Swift: $(swift --version 2>&1 | head -n 1)"
for tool in cmake ninja gcc make curl tar; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required tool missing: $tool" >&2; exit 1; }
done

# ------------------------------------------------------------------
# 3. Build SDL3, SDL3_image, SDL3_ttf from pinned releases
# ------------------------------------------------------------------
SDL_ROOT="$DEV_ROOT/SDL3"
mkdir -p "$SDL_ROOT"
# Let SDL_image/SDL_ttf find the just-built SDL3
export CMAKE_PREFIX_PATH="$SDL_ROOT"

build_sdl() {
    local repo="$1" asset="$2" version="$3" extra_flags="$4"
    local tarball="$WORK_DIR/${asset}-${version}.tar.gz"
    local srcdir="$WORK_DIR/${asset}-${version}-src"
    local builddir="$WORK_DIR/${asset}-${version}-build"

    echo "=== Building $asset $version ==="
    curl -sSL -o "$tarball" \
        "https://github.com/libsdl-org/${repo}/releases/download/release-${version}/${asset}-${version}.tar.gz"
    rm -rf "$srcdir" "$builddir"
    mkdir -p "$srcdir"
    tar xzf "$tarball" -C "$srcdir" --strip-components=1
    # shellcheck disable=SC2086
    cmake -S "$srcdir" -B "$builddir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$SDL_ROOT" \
        -DBUILD_SHARED_LIBS=ON $extra_flags
    cmake --build "$builddir"
    cmake --install "$builddir"
    rm -rf "$srcdir" "$builddir" "$tarball"
}

build_sdl "SDL" "SDL3" "$SDL3_VERSION" "-DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF"
build_sdl "SDL_image" "SDL3_image" "$SDL3_IMAGE_VERSION" "-DSDLIMAGE_VENDORED=OFF -DSDLIMAGE_AVIF=OFF -DSDLIMAGE_JXL=OFF"
build_sdl "SDL_ttf" "SDL3_ttf" "$SDL3_TTF_VERSION" "-DSDLTTF_VENDORED=OFF -DSDLTTF_PLUTOSVG=OFF"

# ------------------------------------------------------------------
# 4. Build zlib-ng from pinned release
# ------------------------------------------------------------------
ZLIB_ROOT="$DEV_ROOT/zlib-ng"
mkdir -p "$ZLIB_ROOT"
echo "=== Building zlib-ng $ZLIB_NG_VERSION ==="
curl -sSL -o "$WORK_DIR/zlib-ng.tar.gz" \
    "https://github.com/zlib-ng/zlib-ng/archive/refs/tags/$ZLIB_NG_VERSION.tar.gz"
mkdir -p "$WORK_DIR/zlib-ng-src"
tar xzf "$WORK_DIR/zlib-ng.tar.gz" -C "$WORK_DIR/zlib-ng-src" --strip-components=1
cmake -S "$WORK_DIR/zlib-ng-src" -B "$WORK_DIR/zlib-ng-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$ZLIB_ROOT" \
    -DBUILD_SHARED_LIBS=ON \
    -DZLIB_COMPAT=OFF \
    -DBUILD_TESTING=OFF \
    -DWITH_GTEST=OFF
cmake --build "$WORK_DIR/zlib-ng-build"
cmake --install "$WORK_DIR/zlib-ng-build"
rm -rf "$WORK_DIR/zlib-ng-src" "$WORK_DIR/zlib-ng-build" "$WORK_DIR/zlib-ng.tar.gz"

# ------------------------------------------------------------------
# 5. Download PDFium (runtime-optional, dlopen'd by the app)
# ------------------------------------------------------------------
PDFIUM_ROOT="$DEV_ROOT/pdfium"
mkdir -p "$PDFIUM_ROOT"
echo "=== Downloading PDFium ($PDFIUM_ASSET) ==="
curl -sSL -o "$WORK_DIR/pdfium.tgz" \
    "https://github.com/bblanchon/pdfium-binaries/releases/download/$PDFIUM_TAG/$PDFIUM_ASSET"
tar xzf "$WORK_DIR/pdfium.tgz" -C "$PDFIUM_ROOT"
rm -f "$WORK_DIR/pdfium.tgz"

# ------------------------------------------------------------------
# 6. Download DXC (HLSL -> SPIR-V; x86_64 only, no ARM64 Linux build)
# ------------------------------------------------------------------
if [ "$ARCH" = "x86_64" ]; then
    DXC_ROOT="$DEV_ROOT/dxc"
    mkdir -p "$DXC_ROOT"
    echo "=== Downloading DXC $DXC_VERSION ==="
    curl -sSL -o "$WORK_DIR/dxc.tar.gz" \
        "https://github.com/microsoft/DirectXShaderCompiler/releases/download/$DXC_VERSION/$DXC_ASSET"
    tar xzf "$WORK_DIR/dxc.tar.gz" -C "$DXC_ROOT"
    rm -f "$WORK_DIR/dxc.tar.gz"
    chmod +x "$DXC_ROOT/bin/dxc"
    "$DXC_ROOT/bin/dxc" --version
    echo "Add DXC to your PATH (e.g. in ~/.bashrc):"
    echo "  export PATH=\"$DXC_ROOT/bin:\$PATH\""
else
    echo "WARNING: no DXC binary for $ARCH (upstream ships Linux x86_64 only)."
    echo "Shader compilation will be skipped; copy .spv files from an x64 build if needed."
fi

# ------------------------------------------------------------------
# 7. Verify + next steps
# ------------------------------------------------------------------
echo ""
echo "--- Installed ---"
ls "$SDL_ROOT/lib"/libSDL3*.so* "$ZLIB_ROOT/lib"/libz-ng.so* 2>/dev/null
find "$PDFIUM_ROOT" -name "libpdfium.so"
echo ""
echo "### Setup complete. Build with: ./Engine/EngineAsBuilt/compile-linux.sh \"$DEV_ROOT\" ###"
