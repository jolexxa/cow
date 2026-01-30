#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

rm -rf coverage

dart test --coverage=coverage

dart pub global activate coverage 1.15.0 >/dev/null

dart pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --report-on=lib \
  --check-ignore \
  --ignore-files='**/*.g.dart'

dart run test_coverage_badge --file coverage/lcov.info

if command -v genhtml >/dev/null 2>&1; then
  genhtml coverage/lcov.info --output-directory coverage/html >/dev/null
  if command -v open >/dev/null 2>&1; then
    open coverage/html/index.html
  fi
fi
