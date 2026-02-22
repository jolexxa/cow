# MLX Dart

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

Thin Dart FFI bindings for [CowMLX](../cow_mlx/README.md), the MLX Swift inference backend.

## Setup

This package requires the `libCowMLX.dylib` native library built from [cow_mlx](../cow_mlx/README.md).

Build the native library:

```sh
dart tool/build_mlx.dart
```

Generate bindings:

```sh
dart run ffigen --config tool/ffigen.yaml
```

## Usage

```dart
import 'package:mlx_dart/mlx_dart.dart';

final mlx = MlxDart.open(libraryPath: '/absolute/path/to/libCowMLX.dylib');
```

The generated bindings in `lib/src/bindings/cow_mlx_bindings.dart` expose the full C API surface of CowMLX.

---

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
