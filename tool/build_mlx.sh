#!/usr/bin/env bash
set -euo pipefail

# Build CowMLX dynamic library.
#
# Usage:
#   tool/build_mlx.sh [args...]

exec "$(dirname "$0")/../packages/cow_mlx/build.sh" "$@"
