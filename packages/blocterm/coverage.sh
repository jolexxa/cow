#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

dart test --coverage=coverage

dart pub global activate coverage 1.15.0 >/dev/null

dart pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --report-on=lib

dart run test_coverage_badge --file coverage/lcov.info
