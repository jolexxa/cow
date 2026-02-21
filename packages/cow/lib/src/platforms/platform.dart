import 'dart:ffi';
import 'dart:io';

import 'package:cow/src/app/app_model_profile.dart';
import 'package:cow/src/app/app_model_profiles.dart';
import 'package:cow/src/app/cow_paths.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:mlx_dart/mlx_dart.dart';
import 'package:nocterm/nocterm.dart';
import 'package:path/path.dart' as p;

sealed class OSPlatform {
  const OSPlatform();

  factory OSPlatform.current() {
    if (Platform.isMacOS) {
      return MacOS();
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

  /// Default primary model ID for this platform.
  String get defaultPrimaryModelId;

  /// Default lightweight (summary) model ID for this platform.
  String get defaultLightweightModelId;

  static const int defaultContextSize = 10000;
  static const int batchSize = 512;

  /// Build backend-specific runtime options for the given [profile].
  BackendRuntimeOptions buildRuntimeOptions({
    required AppModelProfile profile,
    required CowPaths cowPaths,
    required int seed,
    int? maxOutputTokensOverride,
  });

  /// Build [SamplingOptions] from a model's runtime config.
  SamplingOptions buildSampling(AppModelProfile profile, int seed) {
    final config = profile.runtimeConfig;
    return SamplingOptions(
      seed: seed,
      temperature: config.temperature,
      topK: config.topK,
      topP: config.topP,
      minP: config.minP,
      penaltyRepeat: config.penaltyRepeat,
      penaltyLastN: config.penaltyLastN,
    );
  }

  /// Build [LlamaCppRuntimeOptions] — shared across all platforms.
  LlamaCppRuntimeOptions buildLlamaCppOptions({
    required AppModelProfile profile,
    required CowPaths cowPaths,
    required SamplingOptions sampling,
    required int contextSize,
    required int maxOutputTokens,
    required int nGpuLayers,
  }) {
    return LlamaCppRuntimeOptions(
      modelPath: cowPaths.modelEntrypoint(profile.downloadableModel),
      libraryPath: resolveLlamaLibraryPath(),
      modelOptions: LlamaModelOptions(
        nGpuLayers: nGpuLayers,
        useMmap: true,
        useMlock: true,
      ),
      maxOutputTokensDefault: maxOutputTokens,
      samplingOptions: sampling,
      contextOptions: LlamaContextOptions(
        contextSize: contextSize,
        nBatch: batchSize,
        nThreads: defaultThreadCount(),
        nThreadsBatch: defaultThreadCount(),
        useFlashAttn: useFlashAttn,
      ),
    );
  }
}

class MacOS extends OSPlatform {
  MacOS();

  /// Resolved MLX library path, or null if unavailable.
  late final String? mlxLibraryPath = _findMlxLibraryPath();

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
    final repoRoot = scriptDir.parent.parent.parent;
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

  @override
  String get defaultPrimaryModelId =>
      mlxLibraryPath != null ? AppModelId.qwen3Mlx.name : AppModelId.qwen3.name;

  @override
  String get defaultLightweightModelId => mlxLibraryPath != null
      ? AppModelId.qwen25_3bMlx.name
      : AppModelId.qwen25_3b.name;

  @override
  BackendRuntimeOptions buildRuntimeOptions({
    required AppModelProfile profile,
    required CowPaths cowPaths,
    required int seed,
    int? maxOutputTokensOverride,
  }) {
    final config = profile.runtimeConfig;
    final contextSize = config.contextSize ?? OSPlatform.defaultContextSize;
    final maxOut = maxOutputTokensOverride ?? (contextSize ~/ 2);
    final sampling = buildSampling(profile, seed);

    if (profile.backend == InferenceBackend.mlx) {
      if (mlxLibraryPath == null) {
        throw Exception(
          'Model "${profile.downloadableModel.id}" requires the MLX backend, '
          'but the MLX library was not found. '
          'MLX is only available on Apple Silicon Macs.',
        );
      }
      return MlxRuntimeOptions(
        modelPath: cowPaths.modelDir(profile.downloadableModel),
        libraryPath: mlxLibraryPath!,
        contextSize: contextSize,
        maxOutputTokensDefault: maxOut,
        samplingOptions: sampling,
      );
    }

    return buildLlamaCppOptions(
      profile: profile,
      cowPaths: cowPaths,
      sampling: sampling,
      contextSize: contextSize,
      maxOutputTokens: maxOut,
      nGpuLayers: nGpuLayers,
    );
  }

  String? _findMlxLibraryPath() {
    if (Abi.current() != Abi.macosArm64) return null;

    final executableDir = File(Platform.resolvedExecutable).parent;
    final bundledPath = MlxDart.resolveLibraryPath(
      executableDir: executableDir,
    );
    if (File(bundledPath).existsSync()) {
      return bundledPath;
    }

    // During `dart run`, fall back to dev paths relative to the script.
    final scriptDir = File.fromUri(Platform.script).parent;
    final repoRoot = scriptDir.parent.parent.parent;
    final devPaths = [
      // Prebuilt assets.
      p.join(
        repoRoot.path,
        'packages',
        'mlx_dart',
        'assets',
        'native',
        'macos',
        'arm64',
        'libCowMLX.dylib',
      ),
      // cow_mlx xcodebuild output (required for Metal shaders).
      p.join(
        repoRoot.path,
        'packages',
        'cow_mlx',
        '.build',
        'xcode',
        'Build',
        'Products',
        'Release',
        'libCowMLX.dylib',
      ),
      // cow_mlx SwiftPM release build output.
      p.join(
        repoRoot.path,
        'packages',
        'cow_mlx',
        '.build',
        'release',
        'libCowMLX.dylib',
      ),
      // cow_mlx SwiftPM debug build output.
      p.join(
        repoRoot.path,
        'packages',
        'cow_mlx',
        '.build',
        'debug',
        'libCowMLX.dylib',
      ),
    ];
    for (final devPath in devPaths) {
      if (File(devPath).existsSync()) {
        return devPath;
      }
    }
    return null;
  }
}

class Linux extends OSPlatform {
  const Linux();

  @override
  String get defaultPrimaryModelId => AppModelId.qwen3.name;

  @override
  String get defaultLightweightModelId => AppModelId.qwen25_3b.name;

  @override
  BackendRuntimeOptions buildRuntimeOptions({
    required AppModelProfile profile,
    required CowPaths cowPaths,
    required int seed,
    int? maxOutputTokensOverride,
  }) {
    if (profile.backend == InferenceBackend.mlx) {
      throw Exception(
        'Model "${profile.downloadableModel.id}" requires the MLX backend, '
        'which is only available on macOS with Apple Silicon.',
      );
    }

    final config = profile.runtimeConfig;
    final contextSize = config.contextSize ?? OSPlatform.defaultContextSize;
    final maxOut = maxOutputTokensOverride ?? (contextSize ~/ 2);
    final sampling = buildSampling(profile, seed);

    return buildLlamaCppOptions(
      profile: profile,
      cowPaths: cowPaths,
      sampling: sampling,
      contextSize: contextSize,
      maxOutputTokens: maxOut,
      nGpuLayers: nGpuLayers,
    );
  }

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
    final repoRoot = scriptDir.parent.parent.parent;
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
