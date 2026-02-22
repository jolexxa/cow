import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Entry point for loading the CowMLX native library.
class MlxDart {
  factory MlxDart.open({required String libraryPath}) {
    final dylib = DynamicLibrary.open(libraryPath);
    return MlxDart._(dylib);
  }

  MlxDart._(this.dylib);

  final DynamicLibrary dylib;

  static String defaultLibraryFileName() => 'libCowMLX.dylib';

  /// Resolves the library path, checking bundled location first, then
  /// falling back to dev assets.
  static String resolveLibraryPath({required Directory executableDir}) {
    // Bundled path: ../lib/<libname> relative to executable.
    final bundled = p.join(
      executableDir.path,
      '..',
      'lib',
      defaultLibraryFileName(),
    );
    if (File(bundled).existsSync()) {
      return bundled;
    }

    // Dev path: the executable dir itself (for dart run).
    final devPath = p.join(executableDir.path, defaultLibraryFileName());
    if (File(devPath).existsSync()) {
      return devPath;
    }

    // Return the bundled path even if it doesn't exist — the caller
    // will get a clear error from DynamicLibrary.open.
    return bundled;
  }
}
