# Contributing

Thanks for your interest in improving Cow!

## Native llama.cpp Libraries

This project ships and loads native llama.cpp libraries via the `llama_cpp_dart` package. The library path is **always explicit** and is wired from the app entrypoint down to the FFI loader.

### 1) Where the native libraries come from

- Prebuilt native binaries live under `packages/llama_cpp_dart/assets/native/...`.
- A local checkout of llama.cpp lives under `packages/llama_cpp_dart/third_party/llama.cpp` (submodule).
- For development, assets can be downloaded via `tool/download_llama_assets.dart` (see `README.md` for setup details).

### 2) How the library path is resolved

Library resolution happens once, near app initialization, and yields a concrete file path.

- `OSPlatform.resolveLlamaLibraryPath()` in `lib/src/platforms/platform.dart`:
  - Calls `LlamaCpp.resolveLibraryPath(executableDir: File(Platform.resolvedExecutable).parent)` to locate a bundled library near the executable.
  - If that path does not exist (e.g., `dart run`), it falls back to a **dev assets** path under `packages/llama_cpp_dart/assets/native/...`.
- `LlamaCpp.resolveLibraryPath(...)` in `packages/llama_cpp_dart/lib/src/llama_cpp_dart.dart`:
  - Checks for a bundled library in `../lib/` relative to the executable.
  - Then checks `./lib/` relative to the executable.
  - Finally falls back to `<executableDir>/<defaultLibraryFileName>`.

The result is a concrete file path string. From this point forward, the path is treated as **required** and does not fall back to defaults again.

### 3) How the path is threaded through the app

Once resolved, the path is passed through all layers explicitly:

- `AppInfo.initialize()` in `lib/src/app/app_info.dart`:
  - Calls `platform.resolveLlamaLibraryPath()`.
  - Creates `LlamaRuntimeOptions(libraryPath: ...)` for both the main and summary runtimes.
- UI setup in `lib/src/features/chat/view/chat_page.dart`:
  - Instantiates `CowBrains(libraryPath: appInfo.llamaRuntimeOptions.libraryPath)`.
- Brain API in `packages/cow_brain/lib/src/cow_brain_api.dart`:
  - `CowBrains` owns a `LlamaBackend(libraryPath: ...)`.
  - Each `CowBrain` uses that backend and calls `_backend.ensureInitialized()` during `init()`.
- Backend + client in `packages/cow_brain/lib/src/adapters/llama/`:
  - `LlamaBackend` loads bindings using `LlamaClient.openBindings(libraryPath: ...)`.
  - `LlamaClient` then loads ggml backends with `ggml_backend_load_all_from_path(dirname(libraryPath))`.
- FFI loader in `packages/cow_brain/lib/src/adapters/llama/llama_bindings.dart`:
  - `LlamaBindingsLoader.open(libraryPath: ...)` calls `DynamicLibrary.open(libraryPath)`.

## Development Workflow

We use `very_good_cli` (a Dart package) to manage dependencies easily since Cow has multiple packages (see `./packages/`).

```sh
very_good packages get -r # recursively get packages
```

### Inside a Package

```sh
dart format .
dart fix --apply .
dart analyze
dart test
```

If you modify JSON-serializable models, regenerate files as needed:

```sh
dart run build_runner build
```

## Local Model Profiles (format + parse + tools)

Cow treats "model profiles" as the wiring layer between llama.cpp output and the app's message/tool semantics. Each profile defines three pieces:

- Prompt formatter: messages -> token sequence
- Stream parser: raw streamed tokens -> ModelOutput
- Tool parser: extract tool calls from text

### Where profiles live

- Brain-level profiles (runtime behavior): `packages/cow_brain/lib/src/adapters/llama/llama_profiles.dart`
- App-level profiles (which models the app ships/installs): `lib/src/app/app_model_profiles.dart`
- Model file specs/registry/installer logic: `packages/cow_model_manager/lib/src/*.dart`

### Adding a new local model

1) Implement a prompt formatter if the chat template differs:
   - Example: `packages/cow_brain/lib/src/adapters/llama/qwen3_prompt_formatter.dart`
2) Implement a stream parser if tokenization or output markers differ:
   - Example: `packages/cow_brain/lib/src/adapters/llama/qwen_stream_parser.dart`
3) Implement a tool parser if tool-call syntax differs:
   - Example: `packages/cow_brain/lib/src/adapters/llama/qwen3_tool_call_parser.dart`
4) Register the profile in `LlamaProfiles` and update app defaults:
   - `packages/cow_brain/lib/src/adapters/llama/llama_profiles.dart`
   - `lib/src/app/app_model_profiles.dart`
5) Add/update tests in `packages/cow_brain/test` and `packages/cow_model_manager/test`.

Tip: profiles are thin wiring by design—keep logic in formatter/parser classes and keep `llama_profiles.dart` mostly declarative.
