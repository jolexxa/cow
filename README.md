# 🐮 Cow

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

*Holy cow!* Now you can talk back to [the cow][cowsay]!

Cow is just an humble AI for your computer. 🥺

<https://github.com/user-attachments/assets/bc388516-d407-43ab-8496-e1a0ef91897d>

Cow allows you to interact with a local language model, free of charge, as much as you could possibly want — all from the comfort of your own home terminal.

> [!NOTE]
> Cow supports 🍎 [Apple] Silicon and 🐧 Linux x64.

## 🤠 Wrangling

### Binary Install

```sh
curl -fsSL https://raw.githubusercontent.com/jolexxa/cow/main/install.sh | bash
```

This downloads the latest release for your platform and installs it to `~/.local/bin/`.

> [!TIP]
> The first time you run Cow, it will download the required model files automatically from [Hugging Face].

## 🧠 Cow Intelligence

Cow supports two inference backends:

- **[llama.cpp]** via [llama_cpp_dart](./packages/llama_cpp_dart/README.md) — runs GGUF models on CPU or GPU. Llama.cpp is cross platform and works just about anywhere.
- **[MLX]** via [cow_mlx](./packages/cow_mlx/README.md) + [mlx_dart](./packages/mlx_dart/README.md) — runs MLX-format models natively on Apple Silicon. MLX tends to outperform llama.cpp by almost an order of magnitude or more on Apple Silicon hardware.

A higher-level package called [cow_brain](./packages/cow_brain/README.md) wraps both backends behind a common `InferenceRuntime` interface and enables high-level agentic functionality (reasoning, tool use, context management).

On Apple Silicon, Cow uses MLX with `Qwen 3-8B 4-bit` for primary interactions and `Qwen 2.5-3B Instruct 4-bit` for lightweight summarization. On Linux, Cow uses llama.cpp with the equivalent GGUF models.

Cow cannot support arbitrary models. Most models require prompts to follow a specific template, usually provided as [jinja] code.

> [!TIP]
> Since Cow tries to avoid re-tokenizing the message history on each interaction, one would need to implement the template for any new models in native Dart code. This may involve writing a [prompt formatter](packages/cow_brain/lib/src/adapters/qwen3_prompt_formatter.dart), [stream parser](packages/cow_brain/lib/src/adapters/universal_stream_parser.dart), and/or [tool call extractor](packages/cow_brain/lib/src/adapters/extractors/json_tool_call_extractor.dart) before hooking it up in the [model profiles](packages/cow_brain/lib/src/adapters/model_profiles.dart), [app model profiles](packages/cow/lib/src/app/app_model_profiles.dart), and [main app](packages/cow/lib/src/app/app.dart).

One could change the context size in [AppInfo](./packages/cow/lib/src/app/app_info.dart). One should be sure they have enough memory to support the context size they choose or they might just put their computer out to pasture.

## 📦 Packages

Cow is currently a monorepo. All packages live under `packages/`.

| Package                                            | Description                                                                                                  |
|----------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| [cow](./packages/cow/)                             | Main terminal application — orchestrates backends, UI, and model management                                  |
| [cow_brain](./packages/cow_brain/)                 | Agentic inference layer — reasoning, tool use, context management, and a common `InferenceRuntime` interface |
| [cow_model_manager](./packages/cow_model_manager/) | Model installer — downloads and manages LLM model files                                                      |
| [llama_cpp_dart](./packages/llama_cpp_dart/)       | Dart FFI bindings for [llama.cpp]                                                                            |
| [cow_mlx](./packages/cow_mlx/)                     | MLX Swift inference backend (macOS only) — built separately via [Xcode](#4-build-mlx-macos-only)             |
| [mlx_dart](./packages/mlx_dart/)                   | Dart FFI bindings for [cow_mlx](./packages/cow_mlx/)                                                         |
| [blocterm](./packages/blocterm/)                   | Bridges [bloc] and [nocterm] for reactive terminal UIs                                                       |
| [logic_blocks](./packages/logic_blocks/)           | Human-friendly hierarchical state machines for Dart                                                          |
| [collections](./packages/collections/)             | Utility collection types used across packages                                                                |

## 💻 Terminal

For a beautiful Terminal UI (TUI), Cow uses [nocterm]. Nocterm is also still in active development. Cow introduces a package called [blocterm](./packages/blocterm/README.md) to enable [bloc] to be used as if it were a typical Flutter application.

Cow-related contributions to Nocterm:

- [fix: quantize colors in environments without true color support](https://github.com/Norbert515/nocterm/pull/36)
- [feat: text selection](https://github.com/Norbert515/nocterm/pull/40)
- [fix: scrollbar position](https://github.com/Norbert515/nocterm/pull/41)
- [fix: render object attach](https://github.com/Norbert515/nocterm/pull/46)

## 🤝 Contributing

### Development Setup

#### Prerequisites

- [Dart SDK] (the easiest way is to use [FVM] to install Flutter, which includes Dart — without a version manager, you'll end up in a stampede)
- [Xcode] (macOS only — required to build the MLX Swift library and compile Metal shaders)

#### 1. Clone with submodules

Cow includes [llama.cpp] as a git submodule (used for FFI bindings). The `--recursive` flag pulls it in automatically.

```sh
git clone --recursive https://github.com/jolexxa/cow.git
cd cow
```

#### 2. Install dependencies

Cow is a monorepo with multiple Dart packages under `packages/`.

```sh
dart tool/pub_get.dart
```

#### 3. Download llama.cpp native libraries

Downloads prebuilt llama.cpp binaries for your platform (macOS ARM64 or Linux x64) and places them in `packages/llama_cpp_dart/assets/native/`.

```sh
dart tool/download_llama_assets.dart
```

#### 4. Build MLX (macOS only)

Builds the `CowMLX` Swift dynamic library. This requires Xcode (not just the command-line tools) because MLX uses Metal shaders that SwiftPM alone can't compile.

```sh
dart tool/build_mlx.dart
```

#### 5. Run

```sh
dart run packages/cow/bin/cow.dart
```

### Developer Scripts

All scripts are in `./tool/` and most accept an optional package name (e.g., `cow_brain`, `blocterm`).

```sh
dart tool/pub_get.dart [pkg]      # dart pub get (one or all)
dart tool/test.dart [pkg]         # run Dart tests (one or all)
dart tool/analyze.dart [pkg]      # dart analyze --fatal-infos
dart tool/format.dart [pkg]       # dart format (add --check for CI mode)
dart tool/coverage.dart [pkg]     # tests + lcov coverage report
dart tool/codegen.dart [pkg]      # build_runner / ffigen code generation
dart tool/build_mlx.dart          # build CowMLX Swift library
dart tool/checks.dart             # full CI check (format → analyze → build → test → coverage)
```

### Model Profiles

Cow treats "model profiles" as the wiring layer between raw inference output and the app's message/tool semantics. Each profile defines three pieces:

- **Prompt formatter** — converts messages into a token sequence matching the model's chat template
- **Stream parser** — converts raw streamed tokens into structured `ModelOutput`
- **Tool parser** — extracts tool calls from model text output

Profiles live in:

- [cow_brain model profiles](packages/cow_brain/lib/src/adapters/model_profiles.dart) — runtime behavior
- [app model profiles](packages/cow/lib/src/app/app_model_profiles.dart) — which models the app ships
- [cow_model_manager](packages/cow_model_manager/lib/src/) — model file specs, registry, and installer logic

To add a new local model, implement the formatter/parser/extractor as needed, register the profile, and add tests. Profiles are thin wiring by design — keep logic in the formatter/parser classes and keep the profile declarations mostly declarative.

## 🎬 Credits

Cow is grateful to [Alibaba Cloud] for releasing the Qwen models under the permissive Apache 2.0 license. See the [credits](./CREDITS.md) for the full license.

Cow itself is licensed under the permissive MIT license. Yee-haw!

---

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[nocterm]: https://pub.dev/packages/nocterm
[MLX]: https://github.com/ml-explore/mlx
[cowsay]: https://en.wikipedia.org/wiki/Cowsay
[bloc]: https://pub.dev/packages/bloc
[Hugging Face]: https://huggingface.co/
[Dart SDK]: https://dart.dev/get-dart
[FVM]: https://fvm.app/
[Apple]: https://farmhouseguide.com/what-fruits-can-cows-eat/#Apples
[Alibaba Cloud]: https://www.alibabacloud.com/
[jinja]: https://jinja.palletsprojects.com/
[llama.cpp]: https://github.com/ggml-org/llama.cpp
[Xcode]: https://developer.apple.com/xcode/
