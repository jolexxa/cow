import 'dart:ffi';
import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:nocterm/nocterm.dart';
import 'package:path/path.dart' as p;

sealed class OSPlatform {
  const OSPlatform();

  factory OSPlatform.current() {
    if (Platform.isMacOS) {
      return const MacOS();
    }
    if (Platform.isLinux) {
      return const Linux();
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  int get nGpuLayers;

  int defaultThreadCount() {
    final cores = Platform.numberOfProcessors;
    if (cores <= 4) {
      return cores - 1;
    }
    return cores - 2;
  }

  /// Shuts down the terminal and exits the process with the given [code].
  void exit([int code = 0]) {
    TerminalBinding.instance.requestShutdown(code);
  }

  bool get useFlashAttn;

  int get openFlagWriteOnly;
  int get openFlagCreate;
  int get openFlagAppend;
  int get openFlagTrunc;

  /// Resolves the llama library path.
  ///
  /// Uses [LlamaCpp.resolveLibraryPath] with a fallback to the dev assets
  /// directory when running via `dart run` (where [Platform.resolvedExecutable]
  /// points to the Dart SDK rather than the script).
  String resolveLlamaLibraryPath() {
    // For compiled binaries, Platform.resolvedExecutable is the app itself,
    // so ../lib/ contains the bundled native libraries.
    final executableDir = File(Platform.resolvedExecutable).parent;
    final bundledPath = LlamaCpp.resolveLibraryPath(
      executableDir: executableDir,
    );
    if (File(bundledPath).existsSync()) {
      return bundledPath;
    }

    // During `dart run`, fall back to dev assets relative to the script.
    return _devAssetPath();
  }

  String _devAssetPath();
}

class MacOS extends OSPlatform {
  const MacOS();

  @override
  int get nGpuLayers => -1; // as much on the GPU as possible.

  @override
  bool get useFlashAttn => true;

  @override
  int get openFlagWriteOnly => 0x0001;

  @override
  int get openFlagCreate => 0x0200;

  @override
  int get openFlagAppend => 0x0008;

  @override
  int get openFlagTrunc => 0x0400;

  @override
  String _devAssetPath() {
    final arch = Abi.current();
    if (arch != Abi.macosArm64) {
      throw UnsupportedError('Unsupported architecture: $arch');
    }

    final scriptDir = File.fromUri(Platform.script).parent;
    final repoRoot = scriptDir.parent;
    return p.join(
      repoRoot.path,
      'packages',
      'llama_cpp_dart',
      'assets',
      'native',
      'macos',
      'arm64',
      'libllama.0.dylib',
    );
  }
}

class Linux extends OSPlatform {
  const Linux();

  @override
  void exit([int code = 0]) {
    // On Linux, Dart's exit() can terminate before stdin's termios settings
    // are fully restored, leaving the terminal in raw mode (no echo, no line
    // buffering). Force a reset via stty before the normal shutdown path.
    //
    // Even though Nocterm attempts to restore terminal settings on exit, it
    // doesn't always seem to complete before the process ends.
    try {
      Process.runSync('stty', ['-F', '/dev/tty', 'sane']);
    } on Object catch (_) {}
    super.exit(code);
  }

  @override
  int get nGpuLayers => -1; // as much on the GPU as possible.

  @override
  bool get useFlashAttn => false;

  @override
  int get openFlagWriteOnly => 0x0001;

  @override
  int get openFlagCreate => 0x0040;

  @override
  int get openFlagAppend => 0x0400;

  @override
  int get openFlagTrunc => 0x0200;

  @override
  String _devAssetPath() {
    final arch = Abi.current();
    if (arch != Abi.linuxX64) {
      throw UnsupportedError('Unsupported architecture: $arch');
    }

    final scriptDir = File.fromUri(Platform.script).parent;
    final repoRoot = scriptDir.parent;
    return p.join(
      repoRoot.path,
      'packages',
      'llama_cpp_dart',
      'assets',
      'native',
      'linux',
      'x64',
      'libllama.so',
    );
  }
}
