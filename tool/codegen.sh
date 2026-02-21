#!/usr/bin/env bash
set -euo pipefail

# Run build_runner for JSON serialization code generation.
#
# Usage:
#   tool/codegen.sh             # all packages with build_runner
#   tool/codegen.sh cow_brain   # just cow_brain

cd "$(dirname "$0")/.."

# Packages that use build_runner for code generation.
CODEGEN_PACKAGES=(
  packages/cow
  packages/cow_brain
)

run_codegen() {
  local pkg="$1"
  echo "=== Codegen: $pkg ==="
  (cd "$pkg" && dart run build_runner build --delete-conflicting-outputs)
  echo ""
}

if [ $# -gt 0 ]; then
  target="$1"
  if [ -d "packages/$target" ]; then
    run_codegen "packages/$target"
  elif [ -d "$target" ]; then
    run_codegen "$target"
  else
    echo "Unknown package: $target"
    exit 1
  fi
  exit 0
fi

for pkg in "${CODEGEN_PACKAGES[@]}"; do
  run_codegen "$pkg"
done

echo "Code generation complete."
