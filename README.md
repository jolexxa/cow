# 🐮 Cow

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

*Holy cow!* Now you can talk back to [the cow][cowsay]!

Cow is just an humble AI for your computer. 🥺

<https://github.com/user-attachments/assets/bc388516-d407-43ab-8496-e1a0ef91897d>

Cow allows you to interact with a local language model, free of charge, as much as you could possibly want — all from the comfort of your own home terminal.

Cow can reason[^1][^2] and use tools[^3][^4].

> [!NOTE]
> Cow supports 🍎 [Apple] Silicon and 🐧 Linux x64.

## 🤠 Wrangling

### Binary Install

```sh
curl -fsSL https://raw.githubusercontent.com/jolexxa/cow/main/install.sh | bash
```

This downloads the latest release for your platform and installs it to `~/.local/bin/`.

### Development Setup

To build from source, you will need to have [Dart SDK] installed.

> [!TIP]
> Ironically, the easiest way to get started with Dart is to use [FVM] to install Flutter. Without a version manager, you'll end up in a stampede.

```sh

# Cow uses a submodule for llama_cpp, so this clones everything you need.
# These headers are used for the llama_cpp_dart FFI bindings package
# included with Cow.
git clone --recursive https://github.com/jolexxa/cow.git

# Download the required native libraries for llama_cpp based on the
# host operating system (macOS ARM64 or Linux x64):
dart ./tool/download_llama_assets.dart

# Get packages recursively for all sub-projects:
dart pub global activate very_good_cli
very_good packages get -r

# To build only:
# dart build cli

dart run bin/cow.dart
```

The first time you run Cow, it will download the required model files automatically from [Hugging Face].

> [!WARNING]
> Cow is early in development. Much of Cow's client code is expected to change substantially. **Don't do anything important with Cow yet.**

## 🧠 Cow Intelligence

Cow introduces a package which uses FFI bindings for [llama_cpp] called [llama_cpp_dart](./packages/llama_cpp_dart/README.md), enabling Cow to run local large language models.

A higher-level packaged called [cow_brain](./packages/cow_brain/README.md) wraps `llama_cpp` and enables high-level agentic functionality.

Cow currently supports models in the `.gguf` format and uses `Qwen 2.5-7B Instruct` for lightweight summarization tasks and `Qwen 3-8B` for primary interactions, including reasoning and tool execution.

Cow cannot support arbitrary models. Most models require prompts to follow a specific template, usually provided as [jinja] code.

> [!TIP]
> Since Cow tries to avoid re-tokenizing the message history on each interaction, one would need to implement the template for any new models in native Dart code. This may involve writing a [prompt formatter](packages/cow_brain/lib/src/adapters/llama/qwen3_prompt_formatter.dart), [stream parser](packages/cow_brain/lib/src/adapters/llama/qwen_stream_parser.dart), and/or [tool parser](packages/cow_brain/lib/src/adapters/llama/qwen3_tool_call_parser.dart) before hooking it up in the [llama profiles](packages/cow_brain/lib/src/adapters/llama/llama_profiles.dart), [app model profiles](lib/src/app/app_model_profiles.dart), and [main app](lib/src/app/app.dart).

One could change the context size in [AppInfo](./lib/src/app/app_info.dart). One should be sure they have enough memory to support the context size they choose or they might just put their computer out to pasture.

## 💻 Terminal

For a beautiful Terminal UI (TUI), Cow uses [nocterm]. Nocterm is also still in active development. Cow introduces a package called [blocterm](./packages/blocterm/README.md) to enable [bloc] to be used as if it were a typical Flutter application.

Cow-related contributions to Nocterm:

- [fix: quantize colors in environments without true color support](https://github.com/Norbert515/nocterm/pull/36)
- [feat: text selection](https://github.com/Norbert515/nocterm/pull/40)
- [fix: scrollbar position](https://github.com/Norbert515/nocterm/pull/41)

## 🎬 Credits

Cow is grateful to [Alibaba Cloud] for releasing the Qwen models under the permissive Apache 2.0 license. See the [credits](./CREDITS.md) for the full license.

Cow is grateful for its existence in large part to both OpenAI and Anthropic, whose models could almost be considered Cow's parents.

Cow itself is licensed under the permissive MIT license. Yee-haw!

---

[^1]: <https://pmc.ncbi.nlm.nih.gov/articles/PMC2636880/pdf/pone.0004441.pdf>
[^2]: <https://www.animalbehaviorandcognition.org/uploads/journals/17/AB%26C_2017_Vol4%284%29_Marino_Allen.pdf>
[^3]: <https://interestingengineering.com/science/veronika-swiss-cow-cattle-intelligence-study>
[^4]: <https://www.bbc.com/news/articles/cj0n127y74go>

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[nocterm]: https://pub.dev/packages/nocterm
[llama_cpp]: https://github.com/ggml-org/llama.cpp
[cowsay]: https://en.wikipedia.org/wiki/Cowsay
[bloc]: https://pub.dev/packages/bloc
[Hugging Face]: https://huggingface.co/
[Dart SDK]: https://dart.dev/get-dart
[FVM]: https://fvm.app/
[Apple]: https://farmhouseguide.com/what-fruits-can-cows-eat/#Apples
[Alibaba Cloud]: https://www.alibabacloud.com/
[jinja]: https://jinja.palletsprojects.com/
