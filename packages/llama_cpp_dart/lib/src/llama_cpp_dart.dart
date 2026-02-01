import 'dart:ffi';
import 'dart:io';

import 'package:llama_cpp_dart/src/bindings/llama_cpp_bindings.dart';
import 'package:path/path.dart' as p;

/// Loads the llama.cpp dynamic library and exposes generated bindings.
class LlamaCpp {
  /// Open the dynamic library from [libraryPath].
  factory LlamaCpp.open({
    required String libraryPath,
  }) {
    final dylib = DynamicLibrary.open(libraryPath);
    return LlamaCpp._(dylib);
  }
  LlamaCpp._(this.dylib) : bindings = LlamaCppBindings(dylib);

  /// The open dynamic library handle.
  final DynamicLibrary dylib;

  /// Generated FFI bindings.
  final LlamaCppBindings bindings;

  /// Resolve the default dynamic library path.
  static String resolveLibraryPath({
    Directory? executableDir,
  }) {
    final baseDir = executableDir ?? File(Platform.resolvedExecutable).parent;
    final bundleLibPath = p.normalize(
      p.join(baseDir.path, '..', 'lib', defaultLibraryFileName()),
    );
    if (File(bundleLibPath).existsSync()) {
      return bundleLibPath;
    }

    final siblingLibPath = p.join(
      baseDir.path,
      'lib',
      defaultLibraryFileName(),
    );
    if (File(siblingLibPath).existsSync()) {
      return siblingLibPath;
    }

    return p.join(baseDir.path, defaultLibraryFileName());
  }

  /// Default library file name for the current platform.
  static String defaultLibraryFileName() {
    if (Platform.isMacOS) return 'libllama.0.dylib';
    if (Platform.isLinux) return 'libllama.so';
    if (Platform.isWindows) return 'llama.dll';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
