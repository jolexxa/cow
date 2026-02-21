#!/usr/bin/env bash
set -euo pipefail

# Run code generation (build_runner + ffigen) across packages.
#
# Usage:
#   tool/codegen.sh             # all packages
#   tool/codegen.sh cow_brain   # just cow_brain

cd "$(dirname "$0")/.."

# Packages that use build_runner for code generation.
BUILDRUNNER_PACKAGES=(
  packages/cow
  packages/cow_brain
)

# Packages that use dart ffigen for native bindings generation.
FFIGEN_PACKAGES=(
  packages/mlx_dart
  packages/llama_cpp_dart
)

run_build_runner() {
  local pkg="$1"
  echo "=== build_runner: $pkg ==="
  (cd "$pkg" && dart run build_runner build --delete-conflicting-outputs)
  echo ""
}

run_ffigen() {
  local pkg="$1"
  echo "=== ffigen: $pkg ==="
  (cd "$pkg" && dart run ffigen --config tool/ffigen.yaml)
  echo ""
}

if [ $# -gt 0 ]; then
  target="$1"
  # Resolve to a packages/ path if needed.
  if [ -d "packages/$target" ]; then
    target="packages/$target"
  elif [ ! -d "$target" ]; then
    echo "Unknown package: $target"
    exit 1
  fi

  # Run whichever generators apply to this package.
  ran=false
  for pkg in "${BUILDRUNNER_PACKAGES[@]}"; do
    if [ "$pkg" = "$target" ]; then
      run_build_runner "$target"
      ran=true
    fi
  done
  for pkg in "${FFIGEN_PACKAGES[@]}"; do
    if [ "$pkg" = "$target" ]; then
      run_ffigen "$target"
      ran=true
    fi
  done

  if [ "$ran" = false ]; then
    echo "No codegen configured for $target"
    exit 1
  fi
  exit 0
fi

for pkg in "${BUILDRUNNER_PACKAGES[@]}"; do
  run_build_runner "$pkg"
done

for pkg in "${FFIGEN_PACKAGES[@]}"; do
  run_ffigen "$pkg"
done

echo "Code generation complete."
