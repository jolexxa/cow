#!/bin/bash
# Run e2e tests. Execute from packages/cow_e2e/.
set -euo pipefail

REPO_ROOT="$(cd ../.. && pwd)"

# MLX
export COW_MLX_MODEL_PATH="$HOME/.cow/models/qwen3Mlx"
export COW_MLX_SUMMARY_MODEL_PATH="$HOME/.cow/models/qwen25_3bMlx"
export COW_MLX_LIBRARY_PATH="$REPO_ROOT/packages/cow_mlx/.build/release/libCowMLX.dylib"

# llama.cpp
export COW_LLAMA_MODEL_PATH="$HOME/.cow/models/qwen3/Qwen3-8B-Q5_K_M.gguf"
export COW_LLAMA_LIBRARY_PATH="$REPO_ROOT/packages/llama_cpp_dart/assets/native/macos/arm64/libllama.0.dylib"

echo "MLX model:   $COW_MLX_MODEL_PATH"
echo "MLX summary: $COW_MLX_SUMMARY_MODEL_PATH"
echo "MLX library: $COW_MLX_LIBRARY_PATH"
echo "Llama model: $COW_LLAMA_MODEL_PATH"
echo "Llama lib:   $COW_LLAMA_LIBRARY_PATH"

dart test "$@"
