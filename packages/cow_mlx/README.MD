# CowMLX

CowMLX is a Swift wrapper around Apple's local AI model inference engine, MLX. CowMLX exposes a C-compatible interface and compiles to a dynamic library (`libCowMLX.dylib`) that can be used from other languages.

CowMLX handles model loading, token generation, and GPU execution management.

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

CowMLX bridges the Swift-only layers down to a flat C interface (`cow_mlx.h`) so other toolchains can call into it. CowMLX also handles the async-to-sync bridging (Swift concurrency → blocking C calls), thread safety, and per-context GPU stream management that the upstream packages don't provide.

## Architecture

Client apps run inference on multiple AI models at once (one per thread) without blocking the UI. MLX itself doesn't support true multi-threading yet ([confirmed](https://github.com/ml-explore/mlx/issues/3078#issuecomment-3818105000) by [Awni](https://github.com/awni), AI @ Apple). CowMLX works around this by serializing all MLX access through a single dispatch queue while using per-context GPU streams for hardware-level parallelism.

> [!NOTE]
> We could use multiple processes, but our approach has been opting for a single-process architecture and planning forward. All local model inference engines seem to be moving towards multi-threading support, so we don't want to waste time building out process serialization and inter-process communication when the world's about to get a whole lot better. The GPU can only handle so much concurrent work anyway, so performance characteristics would be roughly the same regardless.

```txt
    Thread A                    Thread B
       │                           │
       │  FFI calls                │  FFI calls
       │  (any thread)             │  (any thread)
       │                           │
  ═════╪═══════════════════════════╪══════════════════════
       │    C API (cow_mlx.h)      │
       │    all calls serialize    │
       │    through mlxQueue       │
  ═════╪═══════════════════════════╪══════════════════════
       │                           │
       ▼                           ▼
  ┌─────────────────────────────────────────────────────┐
  │                   mlxQueue                          │
  │            (serial DispatchQueue)                   │
  │                                                     │
  │  All MLX operations run here — one at a time on     │
  │  the CPU. Before each operation, the context's GPU  │
  │  stream is set as the global default via             │
  │  mlx_set_default_stream().                          │
  └──────────────┬──────────────────┬───────────────────┘
                 │                  │
                 ▼                  ▼
  ┌──────────────────┐  ┌──────────────────┐
  │ CowMLXContext 0  │  │ CowMLXContext 1  │
  │                  │  │                  │
  │ stream: GPU:1    │  │ stream: GPU:2    │
  │ iterator (KV $)  │  │ iterator (KV $)  │
  │ detokenizer      │  │ detokenizer      │
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
  │  weights (r/o)   │
  │  tokenizer       │
  │  config          │
  └──────────────────┘

  GPU
  ═══════════════════════════════════════════
  Stream GPU:1 ──▶ [ctx 0 ops]──▶ ┐
                                   ├─ parallel
  Stream GPU:2 ──▶ [ctx 1 ops]──▶ ┘
  ═══════════════════════════════════════════
```

- **Thread safety**: Every C API entry point funnels through `mlxQueue`. No two MLX operations ever execute concurrently on the CPU.
- **GPU parallelism**: Each context owns an `mlx_stream` (GPU command queue). Operations are tagged with that stream when created. The GPU can overlap work from different streams between dispatches.
- **Shared model**: Model weights are read-only after loading. Multiple contexts share one `CowMLXModel` via integer handle IDs that are safe to pass across thread boundaries.
- **Owned state**: KV cache, iterator, detokenizer, stop tokens, and GPU stream are exclusively owned by each context.
