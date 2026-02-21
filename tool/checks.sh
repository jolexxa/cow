#!/usr/bin/env bash
set -euo pipefail

# Full CI-equivalent check. Run this before pushing.
#
# Usage:
#   tool/checks.sh

TOOL_DIR="$(dirname "$0")"

echo "========================================"
echo "  Step 1/6: Format"
echo "========================================"
"$TOOL_DIR/format.sh" --check

echo "========================================"
echo "  Step 2/6: Analyze"
echo "========================================"
"$TOOL_DIR/analyze.sh"

echo "========================================"
echo "  Step 3/6: Build CowMLX"
echo "========================================"
"$TOOL_DIR/build_mlx.sh"

echo "========================================"
echo "  Step 4/6: Test CowMLX (Swift)"
echo "========================================"
"$TOOL_DIR/test_mlx.sh"

echo "========================================"
echo "  Step 5/6: Test (Dart)"
echo "========================================"
"$TOOL_DIR/test.sh"

echo "========================================"
echo "  Step 6/6: Coverage"
echo "========================================"
"$TOOL_DIR/coverage.sh"

echo ""
echo "========================================"
echo "  All checks passed."
echo "========================================"
