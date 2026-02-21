#!/usr/bin/env bash
set -euo pipefail

# Format Dart code for one package or all packages.
#
# Usage:
#   tool/format.sh              # all Dart packages
#   tool/format.sh cow_brain    # just cow_brain
#   tool/format.sh --check      # check only (no writes, exit 1 if unformatted)

cd "$(dirname "$0")/.."

PACKAGES=(
  packages/cow
  packages/collections
  packages/blocterm
  packages/cow_brain
  packages/cow_model_manager
  packages/llama_cpp_dart
  packages/logic_blocks
  packages/mlx_dart
)

CHECK=""
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --check) CHECK="--set-exit-if-changed --output=none" ;;
    *) TARGET="$arg" ;;
  esac
done

run_format() {
  local pkg="$1"
  echo "=== Formatting $pkg ==="
  # shellcheck disable=SC2086
  (cd "$pkg" && dart format $CHECK .)
  echo ""
}

if [ -n "$TARGET" ]; then
  if [ -d "packages/$TARGET" ]; then
    run_format "packages/$TARGET"
  elif [ -d "$TARGET" ]; then
    run_format "$TARGET"
  else
    echo "Unknown package: $TARGET"
    exit 1
  fi
  exit 0
fi

failed=()

for pkg in "${PACKAGES[@]}"; do
  if ! run_format "$pkg"; then
    failed+=("$pkg")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "UNFORMATTED:"
  for pkg in "${failed[@]}"; do
    echo "  - $pkg"
  done
  exit 1
fi

echo "All packages formatted."
