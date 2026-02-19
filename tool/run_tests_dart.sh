#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

packages=(
  .
  packages/collections
  packages/blocterm
  packages/cow_brain
  packages/cow_model_manager
  packages/llama_cpp_dart
  packages/logic_blocks
)

failed=()

for pkg in "${packages[@]}"; do
  if [ ! -d "$pkg/test" ]; then
    continue
  fi
  echo "=== Testing $pkg ==="
  if ! (cd "$pkg" && dart test); then
    failed+=("$pkg")
  fi
  echo ""
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED:"
  for pkg in "${failed[@]}"; do
    echo "  - $pkg"
  done
  exit 1
fi

echo "All packages passed."
