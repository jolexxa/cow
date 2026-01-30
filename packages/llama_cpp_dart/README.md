# Llama Cpp Dart

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![Powered by Mason](https://img.shields.io/endpoint?url=https%3A%2F%2Ftinyurl.com%2Fmason-badge)](https://github.com/felangel/mason)
[![License: MIT][license_badge]][license_link]

Thin Dart FFI bindings for `llama.cpp`, plus a small loader helper.

## Setup 🧰

This package expects `llama.cpp` as a git submodule in
`packages/llama_cpp_dart/third_party/llama.cpp`, and prebuilt binaries under
`packages/llama_cpp_dart/assets/native`.

1) Initialize the submodule:

```sh
git submodule update --init --recursive packages/llama_cpp_dart/third_party/llama.cpp
```

1) Generate bindings:

```sh
dart run ffigen --config tool/ffigen.yaml
```

1) Build the dynamic library (example for macOS):

```sh
cd third_party/llama.cpp
cmake -B build
cmake --build build --config Release
```

Copy the resulting `libllama.0.dylib` (and its dependency dylibs) into
`packages/llama_cpp_dart/assets/native/macos/arm64/llama-b7818-bin-macos-arm64`.

When you run `dart build cli`, the build hook in this package bundles those
libraries into the CLI output.

## Usage ✨

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

final llama = LlamaCpp.open();
final bindings = llama.bindings;
```

You can override the library location:

```dart
final llama = LlamaCpp.open(libraryPath: '/absolute/path/to/libllama.dylib');
```

---

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
