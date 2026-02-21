#!/bin/bash
set -euo pipefail

# Test CowMLX via xcodebuild (required for Metal shader support).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Testing CowMLX..."

if ! command -v xcodebuild &>/dev/null; then
    echo "Error: xcodebuild not found. Xcode is required to run CowMLX tests."
    exit 1
fi

# TEST_RUNNER_ prefix passes env vars through to the test process.
TEST_RUNNER_MLX_TESTS=1 xcodebuild test \
    -scheme CowMLX \
    -configuration Debug \
    -derivedDataPath .build/xcode \
    -destination 'platform=OS X' \
    2>&1
