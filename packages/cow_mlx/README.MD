# CowMLX

CowMLX is a Swift wrapper around Apple's local AI model inference engine, [MLX]. CowMLX exposes a C-compatible interface and compiles to a dynamic library (`libCowMLX.dylib`) that can be consumed by other languages via FFI (e.g., Dart via [mlx_dart](../mlx_dart/README.md)).

CowMLX handles model loading, tokenization, token generation with KV cache management, custom sampling, and byte-level detokenization.

## Why CowMLX exists

MLX has a C API (`Cmlx`), but it only covers the compute engine — array ops, streams, devices, etc. All of the high-level LLM functionality lives in Swift (and Python) packages with no C API:

```txt
  ┌─────────────────────────────────────────────────────┐
  │  mlx-swift-lm (Swift only, no C API)                │
  │                                                     │
  │  MLXLLM         LLMModelFactory, model registry     │
  │  MLXLMCommon    TokenIterator, KV cache, samplers,  │
  │                 streaming detokenization            │
  ├─────────────────────────────────────────────────────┤
  │  mlx-swift (Swift only, no C API)                   │
  │                                                     │
  │  MLX            Swift wrappers around Cmlx          │
  │  MLXNN          Neural net layers (Linear, RoPE,    │
  │                 Attention, etc.)                    │
  ├─────────────────────────────────────────────────────┤
  │  Cmlx (C API)                                       │
  │                                                     │
  │  Arrays, streams, devices, random, linalg, metal,   │
  │  FFT, transforms — the raw compute engine.          │
  │  No concept of "model", "token", or "generate".     │
  └─────────────────────────────────────────────────────┘
```

CowMLX bridges the Swift-only layers down to a flat C interface (`cow_mlx.h`) so other toolchains can call into it. CowMLX also handles the async-to-sync bridging (Swift concurrency → blocking C calls via `runBlocking` + `DispatchSemaphore`) and thread safety that the upstream packages don't provide.

## Architecture

```txt
    Thread A                    Thread B
       │                           │
       │  FFI calls                │  FFI calls
       │  (any thread)             │  (any thread)
       │                           │
  ═════╪═══════════════════════════╪══════════════════════
       │    C API (cow_mlx.h)      │
       │    @_cdecl exports        │
  ═════╪═══════════════════════════╪══════════════════════
       │                           │
       ▼                           ▼
  ┌─────────────────────────────────────────────────────┐
  │                   runBlocking()                      │
  │             (Task + DispatchSemaphore)               │
  │                                                     │
  │  Bridges sync FFI calls into Swift async context.   │
  │  Model loading serialized via modelLoadLock (NSLock)│
  │  because LLMModelFactory is not thread-safe.        │
  │  GPU eval serialized by MLX's internal evalLock.    │
  └──────────────┬──────────────────┬───────────────────┘
                 │                  │
                 ▼                  ▼
  ┌──────────────────┐  ┌──────────────────┐
  │ CowMLXContext 0  │  │ CowMLXContext 1  │
  │                  │  │                  │
  │ iterator (KV $)  │  │ iterator (KV $)  │
  │ cache [KVCache]  │  │ cache [KVCache]  │
  │ cachedTokens     │  │ cachedTokens     │
  │ stop tokens      │  │ stop tokens      │
  └────────┬─────────┘  └────────┬─────────┘
           │    OWNED per ctx    │
           │                     │
           │   ┌─────────────────┤
           ▼   ▼                 │
  ┌──────────────────┐           │
  │  CowMLXModel 0   │◄──────────┘
  │  (SHARED)        │
  │                  │
  │  container       │  weights (read-only)
  │  tokenizer       │  cached for sync access
  │  config          │  model configuration
  │  decoderType     │  byteLevel or byteFallback
  └──────────────────┘
```

All contexts share the default GPU stream. MLX's internal `evalLock` serializes eval calls, so separate per-context GPU streams don't provide additional parallelism.

### Key design points

- **Thread safety**: Sync-to-async bridging via `runBlocking()` (Swift `Task` + `DispatchSemaphore`). Model loading serialized with `modelLoadLock` (`NSLock`) because `LLMModelFactory` is not thread-safe. GPU eval serialized by MLX's own `evalLock`.
- **Handle registry**: Models and contexts are stored in a thread-safe `HandleRegistry<T>` that maps `Int32` handles to Swift objects. Handles are safe to pass across thread boundaries.
- **Shared model**: Model weights are read-only after loading. Multiple contexts share one `CowMLXModel` via integer handle IDs. Cross-thread sharing uses `cow_mlx_model_get_id` / `cow_mlx_model_from_id`.
- **Owned state**: KV cache, iterator, cached token sequence, and stop tokens are exclusively owned by each context.

### Incremental generation (prefix caching)

Each context tracks `cachedTokens` — the token IDs that produced the current KV cache state. On `generate_begin`, the native side compares incoming tokens against `cachedTokens` to find the common prefix, trims any diverged cache entries, and only prefills new tokens. This avoids re-processing the entire prompt on each turn.

### KV cache management

The C API exposes three cache operations:

- `cow_mlx_cache_token_count` — query current cache size
- `cow_mlx_cache_trim_end` — undo tokens from the end (via `KVCache.trim()`)
- `cow_mlx_cache_trim_front` — sliding window eviction from the front (slices axis 2 of the `state` arrays via getter/setter)

### Byte decoding

Token strings from the vocabulary are converted to raw `[UInt8]` bytes by `ByteDecoder.swift`, dispatched based on the tokenizer's encoding scheme:

- **ByteLevel (GPT-2)** — each byte maps to a unique Unicode character. Used by Qwen, Llama 3+, DeepSeek, StableLM.
- **ByteFallback (SentencePiece)** — raw bytes as `<0xHH>` tokens, metaspace `▁` for leading spaces. Used by Llama 2, Mistral, Mixtral, Phi-3.

The scheme is auto-detected from `tokenizer.json` at model load time (`TokenizerDetector.swift`). Raw bytes are returned to caller, which must handle UTF-8 reassembly.

### Custom sampler

`CustomSampler` implements `MLXLMCommon.LogitSampler` with topK and minP filtering (not provided by Apple's built-in samplers). Full sampling parameter set: `temperature`, `topP`, `topK`, `minP`, `repeatPenalty`, `repeatWindow`, `seed`.

## C API

The full API is defined in [`Sources/CowMLX/include/cow_mlx.h`](Sources/CowMLX/include/cow_mlx.h). All functions are synchronous and blocking. Handles are `Int32` indices (not raw pointers).

[MLX]: https://github.com/ml-explore/mlx
