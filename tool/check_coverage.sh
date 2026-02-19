#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../packages/cow_brain"

echo "=== Running tests with coverage ==="
dart test --coverage=coverage

echo ""
echo "=== Formatting coverage ==="
dart pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --report-on=lib \
  --check-ignore \
  --ignore-files='**/*.g.dart'

echo ""
echo "=== Coverage summary ==="
lcov --summary coverage/lcov.info
