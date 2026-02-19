#!/bin/bash
set -euo pipefail

# Build CowMLX dynamic library.
# Requires Xcode for Metal shader compilation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building CowMLX..."

# xcodebuild is required — Metal shaders can't be compiled by SwiftPM CLI.
if ! command -v xcodebuild &>/dev/null; then
    echo "Error: xcodebuild not found. Xcode is required to build CowMLX."
    exit 1
fi

xcodebuild build \
    -scheme CowMLX \
    -configuration Release \
    -derivedDataPath .build/xcode \
    -destination 'platform=OS X' \
    2>&1

# xcodebuild produces a framework bundle — extract the bare dylib.
FRAMEWORK_BIN=".build/xcode/Build/Products/Release/PackageFrameworks/CowMLX.framework/Versions/A/CowMLX"
DYLIB_PATH=".build/release/libCowMLX.dylib"

if [ ! -f "$FRAMEWORK_BIN" ]; then
    echo "Build succeeded but framework binary not found."
    echo "Expected: $FRAMEWORK_BIN"
    exit 1
fi

mkdir -p .build/release
cp "$FRAMEWORK_BIN" "$DYLIB_PATH"

# MLX looks for mlx.metallib colocated next to the binary.
METALLIB=".build/xcode/Build/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
if [ -f "$METALLIB" ]; then
    cp "$METALLIB" .build/release/mlx.metallib
fi

echo ""
echo "Built successfully: $DYLIB_PATH"
