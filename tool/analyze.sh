#!/usr/bin/env bash
set -euo pipefail

# Run dart analyze for one package or all Dart packages.
#
# Usage:
#   tool/analyze.sh             # all Dart packages
#   tool/analyze.sh cow_brain   # just cow_brain

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

run_analyze() {
  local pkg="$1"
  echo "=== Analyzing $pkg ==="
  (cd "$pkg" && dart analyze --fatal-infos)
  echo ""
}

if [ $# -gt 0 ]; then
  target="$1"
  if [ -d "packages/$target" ]; then
    run_analyze "packages/$target"
  elif [ -d "$target" ]; then
    run_analyze "$target"
  else
    echo "Unknown package: $target"
    exit 1
  fi
  exit 0
fi

failed=()

for pkg in "${PACKAGES[@]}"; do
  if ! run_analyze "$pkg"; then
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

echo "All packages passed analysis."
