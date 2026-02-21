#!/bin/bash
# Run MLX e2e tests. Execute from packages/cow_e2e/.
set -euo pipefail

REPO_ROOT="$(cd ../.. && pwd)"

export COW_MLX_MODEL_PATH="$HOME/.cow/models/qwen3Mlx"
export COW_MLX_SUMMARY_MODEL_PATH="$HOME/.cow/models/qwen25_3bMlx"
export COW_MLX_LIBRARY_PATH="$REPO_ROOT/packages/cow_mlx/.build/release/libCowMLX.dylib"

echo "Primary model: $COW_MLX_MODEL_PATH"
echo "Summary model: $COW_MLX_SUMMARY_MODEL_PATH"
echo "Library: $COW_MLX_LIBRARY_PATH"

dart test "$@"
