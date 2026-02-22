# Cow Brain

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link] [![Coverage][coverage_badge]][coverage_link]

Cow Brain provides high-level agentic functionality for the Cow terminal AI application. It wraps two inference backends — [llama_cpp_dart](../llama_cpp_dart/README.md) and [MLX](../cow_mlx/README.md) (via [mlx_dart](../mlx_dart/README.md)) — behind a common `InferenceRuntime` interface to facilitate interactions with local large language models.

```txt
  ┌─────────────────────────────────────────────────────────────────┐
  │                     CLIENT APP (main thread)                    │
  │                                                                 │
  │  CowBrain / CowBrains<TKey>                                     │
  │  ┌───────────────────────────────────────────────────────────┐  │
  │  │ init() runTurn() sendToolResult() cancel() reset()        │  │
  │  │ dispose()                                                 │  │
  │  └──────────────────────────┬────────────────────────────────┘  │
  │                             │ (delegates everything)            │
  │  BrainHarness               │         ModelServer               │
  │  ┌──────────────────────────┴──────┐  ┌──────────────────────┐  │
  │  │ • Spawns brain isolate          │  │ • Runs in its own    │  │
  │  │ • Serializes BrainRequest →     │  │   isolate            │  │
  │  │   JSON → SendPort               │  │ • Loads/unloads      │  │
  │  │ • Deserializes JSON →           │  │   models (ref-count) │  │
  │  │   AgentEvent stream             │  │ • Shared across all  │  │
  │  │ • Filters events by turnId      │  │   CowBrains          │  │
  │  └──────────────────────────┬──────┘  └──────────────────────┘  │
  └─────────────────────────────┼───────────────────────────────────┘
                                │
              ══════════════════╪════════════════════════
                ISOLATE BOUNDARY (SendPort / ReceivePort)
                All data crosses as JSON maps
              ══════════════════╪════════════════════════
  ┌─────────────────────────────┼───────────────────────────────────┐
  │                        WORKER ISOLATE                           │
  │                             │                                   │
  │  _BrainIsolate (message router)                                 │
  │  ┌──────────────────────────┴────────────────────────────────┐  │
  │  │ handleMessage() switches on BrainRequestType:             │  │
  │  │   init → build everything, send AgentReady                │  │
  │  │   runTurn → add user msg, run agent loop, stream events   │  │
  │  │   toolResult → complete pending Completer<ToolResult>     │  │
  │  │   cancel → set flag + complete cancel completer           │  │
  │  │   reset → new Conversation, reset runtime                 │  │
  │  │   dispose → tear down                                     │  │
  │  └────┬─────────────┬──────────────┬────────────┬────────────┘  │
  │       │             │              │            │               │
  │       ▼             ▼              ▼            ▼               │
  │  ┌─────────┐  ┌────────────┐  ┌──────────┐  ┌──────────────┐    │
  │  │AgentLoop│  │Conversation│  │Context   │  │ Tool         │    │
  │  │(impl of │  │            │  │Manager   │  │ Registry     │    │
  │  │ Agent   │  │            │  │          │  │              │    │
  │  │ Runner) │  │ messages   │  │ sliding  │  │ definitions  │    │
  │  │ steps   │◄─┤ with       │◄─┤ window   │  │ + execute()  │    │
  │  │ through │  │ validation │  │ + prefix │  │ (stubs—real  │    │
  │  │ max N   │  │            │  │ reuse    │  │  exec is on  │    │
  │  └────┬────┘  └────────────┘  └──────────┘  │  main thread)│    │
  │       │                                     └──────────────┘    │
  │       │ calls .next() for each step                             │
  │       ▼                                                         │
  │  ┌──────────────────────────────────────────────────────────┐   │
  │  │ LlmAdapter (interface)                                   │   │
  │  │                                                          │   │
  │  │ InferenceAdapter (implementation)                        │   │
  │  │ ┌────────────────────────────────────────────────────┐   │   │
  │  │ │ • Formats prompt via ModelProfile                  │   │   │
  │  │ │ • Feeds tokens to runtime                          │   │   │
  │  │ │ • Parses streaming output via UniversalStreamParser│   │   │
  │  │ │ • Yields ModelOutput events back to AgentLoop      │   │   │
  │  │ └──────────────────────┬─────────────────────────────┘   │   │
  │  └────────────────────────┼─────────────────────────────────┘   │
  │                           │                                     │
  │       ┌───────────────────┼───────────────────┐                 │
  │       ▼                   ▼                   ▼                 │
  │  ┌──────────┐  ┌─────────────────────┐  ┌──────────────────┐    │
  │  │ Model    │  │ InferenceRuntime    │  │ TokenCounter     │    │
  │  │ Profile  │  │ (interface)         │  │                  │    │
  │  │          │  │                     │  │ countTokens()    │    │
  │  │ format + │  │ ┌─────────────────┐ │  │ (used by Context │    │
  │  │ parse    │  │ │ LlamaCppRuntime │ │  │  Manager)        │    │
  │  │          │  │ │ (llama.cpp/FFI) │ │  └──────────────────┘    │
  │  │          │  │ ├─────────────────┤ │                          │
  │  │          │  │ │ MlxRuntime      │ │                          │
  │  │          │  │ │ (MLX/FFI)       │ │                          │
  │  │          │  │ └─────────────────┘ │                          │
  │  └──────────┘  └─────────────────────┘                          │
  │                                                                 │
  │  Native FFI bridges:                                            │
  │  ┌──────────────────────────────────────────────────────────┐   │
  │  │ LlamaClient + LlamaSamplerChain  → llama.cpp (.so/.dylib)│   │
  │  │ MlxClient + MlxBindings          → CowMLX   (.dylib)    │    │ 
  │  └──────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────┘


  MODEL PROFILES (pluggable per-model behavior)
  ══════════════════════════════════════════════

    ModelProfile
    ├── formatter:    PromptFormatter    (turns messages → prompt string)
    └── streamParser: StreamParser       (turns raw tokens → ModelOutput)
                      └── UniversalStreamParser
                          ├── StreamTokenizer        (tag-aware tokenizer)
                          └── ToolCallExtractor      (extracts tool calls)
                              └── JsonToolCallExtractor

    Profiles registered:
    ┌────────┬────────────────────────┬───────────────────────┐
    │ ID     │ Formatter              │ Stream Parser         │
    ├────────┼────────────────────────┼───────────────────────┤
    │ qwen3  │ Qwen3PromptFormatter   │ UniversalStreamParser │
    │ qwen25 │ Qwen25PromptFormatter  │ UniversalStreamParser │
    └────────┴────────────────────────┴───────────────────────┘

    Auto-detection: ProfileDetector inspects the model's chat
    template metadata to select the correct profile at init time.


  AGENT LOOP (one turn)
  ═════════════════════

    ┌──────────────────────┐
    │ Start turn           │
    │ step = 0             │
    └──────────┬───────────┘
               ▼
    ┌──────────────────────┐    yes
    │ step < maxSteps?     │───────────┐
    │ cancelled?           │           │
    └──────────┬───────────┘           │
            no │                       ▼
               │            ┌───────────────────────┐
               │            │ Prepare ContextSlice  │
               │            │ (sliding window)      │
               │            └──────────┬────────────┘
               │                       ▼
               │            ┌───────────────────────┐
               │            │ LLM.next()            │
               │            │ stream ModelOutput    │
               │            └──────────┬────────────┘
               │                       ▼
               │            ┌──────────────────────┐
               │            │ Tool calls returned? │
               │            └──┬───────────┬───────┘
               │           yes │           │ no
               │               ▼           ▼
               │     ┌─────────────┐  ┌─────────────┐
               │     │Execute tools│  │Yield finish │
               │     │(wait for    │  │Return       │
               │     │ main thread)│  └─────────────┘
               │     └──────┬──────┘
               │            │ append results
               │            │ to conversation
               │            └──► loop back
               │
               ▼
    ┌──────────────────────┐
    │ Yield turnFinished   │
    │ (maxSteps/cancelled) │
    └──────────────────────┘

```

The isolate boundary is the central design constraint. Everything above it is lightweight proxy code, everything below it is where the actual work happens. Tool execution is the interesting part — the agent loop inside the isolate asks for tools, but the main thread actually runs them and sends results back via `sendToolResult()`.

---

[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[coverage_badge]: coverage_badge.svg
[coverage_link]: coverage/lcov.info
