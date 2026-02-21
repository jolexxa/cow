#!/usr/bin/env bash
set -euo pipefail

# Test CowMLX Swift package.
#
# Usage:
#   tool/test_mlx.sh

exec "$(dirname "$0")/../packages/cow_mlx/test.sh" "$@"
