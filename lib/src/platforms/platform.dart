import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

sealed class OSPlatform {
  const OSPlatform();

  factory OSPlatform.current() {
    if (Platform.isMacOS) {
      return const MacOS();
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
  int get nGpuLayers;

  FutureOr<String> resolveLlamaLibraryPath();

  int defaultThreadCount();

  bool get useFlashAttn;
}

class MacOS extends OSPlatform {
  const MacOS();

  @override
  int get nGpuLayers => -1; // as much on the GPU as possible.

  @override
  bool get useFlashAttn => true;

  @override
  FutureOr<String> resolveLlamaLibraryPath() async {
    final arch = Abi.current();

    if (arch != Abi.macosArm64) {
      // Gotta have apple silicon :P
      throw UnsupportedError('Unsupported architecture: $arch');
    }

    final scriptDir = File.fromUri(Platform.script).parent;
    final repoRoot = scriptDir.parent;
    final devPath = p.join(
      repoRoot.path,
      'packages',
      'llama_cpp_dart',
      'assets',
      'native',
      'macos',
      'arm64',
      'llama-b7818-bin-macos-arm64',
      'libllama.0.dylib',
    );
    if (File(devPath).existsSync()) return devPath;

    final packageUri = Uri.parse(
      'package:llama_cpp_dart/assets/native/macos/arm64/'
      'llama-b7818-bin-macos-arm64/libllama.0.dylib',
    );

    final resolved = await Isolate.resolvePackageUri(packageUri);

    if (resolved == null) {
      throw Exception('Could not resolve llama library path $packageUri');
    }

    final candidate = resolved.toFilePath();

    if (File(candidate).existsSync()) return candidate;

    throw Exception('Llama library not found at $candidate');
  }

  @override
  int defaultThreadCount() {
    final cores = Platform.numberOfProcessors;
    if (cores <= 4) {
      return cores - 1;
    }
    return cores - 2;
  }
}
