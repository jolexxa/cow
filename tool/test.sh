#!/usr/bin/env bash
set -euo pipefail

# Run tests for one package or all packages.
#
# Usage:
#   tool/test.sh              # all Dart packages with test/ dirs
#   tool/test.sh cow_brain    # just cow_brain (Dart)
#   tool/test.sh cow_mlx      # just cow_mlx (Swift, via xcodebuild)

TOOL_DIR="$(dirname "$0")"
cd "$TOOL_DIR/.."

DART_PACKAGES=(
  packages/cow
  packages/collections
  packages/blocterm
  packages/cow_brain
  packages/cow_model_manager
  packages/llama_cpp_dart
  packages/logic_blocks
)

run_dart_tests() {
  local pkg="$1"
  if [ ! -d "$pkg/test" ]; then
    return 0
  fi
  echo "=== Testing $pkg ==="
  (cd "$pkg" && dart test)
  echo ""
}

run_mlx_tests() {
  echo "=== Testing packages/cow_mlx (Swift) ==="
  "$TOOL_DIR/test_mlx.sh"
  echo ""
}

if [ $# -gt 0 ]; then
  target="$1"
  # cow_mlx is a Swift package — delegate to test_mlx.sh
  if [ "$target" = "cow_mlx" ] || [ "$target" = "packages/cow_mlx" ]; then
    run_mlx_tests
    exit 0
  fi
  # Allow both "cow_brain" and "packages/cow_brain"
  if [ -d "packages/$target" ]; then
    run_dart_tests "packages/$target"
  elif [ -d "$target" ]; then
    run_dart_tests "$target"
  else
    echo "Unknown package: $target"
    echo "Available: ${DART_PACKAGES[*]} cow_mlx"
    exit 1
  fi
  exit 0
fi

failed=()

for pkg in "${DART_PACKAGES[@]}"; do
  if ! run_dart_tests "$pkg"; then
    failed+=("$pkg")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED:"
  for pkg in "${failed[@]}"; do
    echo "  - $pkg"
  done
  exit 1
fi

echo "All packages passed."
