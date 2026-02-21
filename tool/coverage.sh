#!/usr/bin/env bash
set -euo pipefail

# Run tests with coverage for one package or all coverage-tracked packages.
#
# Usage:
#   tool/coverage.sh cow_brain     # coverage for cow_brain
#   tool/coverage.sh               # coverage for all tracked packages
#
# Exits non-zero if any package fails tests or coverage generation.

cd "$(dirname "$0")/.."

# Packages that require 100% coverage (have coverage.sh in CI).
COVERAGE_PACKAGES=(
  packages/blocterm
  packages/cow_brain
  packages/cow_model_manager
  packages/logic_blocks
)

run_coverage() {
  local pkg="$1"
  local name
  name=$(basename "$pkg")

  if [ ! -d "$pkg/test" ]; then
    echo "=== $name: no test/ directory, skipping ==="
    return 0
  fi

  echo "=== Coverage: $name ==="

  (
    cd "$pkg"
    rm -rf coverage

    dart test --coverage=coverage

    dart pub global run coverage:format_coverage \
      --lcov \
      --in=coverage \
      --out=coverage/lcov.info \
      --report-on=lib \
      --check-ignore \
      --ignore-files='**/*.g.dart'

    if command -v lcov >/dev/null 2>&1; then
      lcov --summary coverage/lcov.info 2>&1
    else
      echo "(install lcov for coverage summary)"
    fi
  )

  echo ""
}

if [ $# -gt 0 ]; then
  target="$1"
  if [ -d "packages/$target" ]; then
    run_coverage "packages/$target"
  elif [ -d "$target" ]; then
    run_coverage "$target"
  else
    echo "Unknown package: $target"
    exit 1
  fi
  exit 0
fi

failed=()

for pkg in "${COVERAGE_PACKAGES[@]}"; do
  if ! run_coverage "$pkg"; then
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

echo "All coverage checks passed."
