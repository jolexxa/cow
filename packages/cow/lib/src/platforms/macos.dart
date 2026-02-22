part of 'os_platform.dart';

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

  // Use MLX for the primary model on macOS whenever possible.
  @override
  AppModelId get defaultPrimaryModelId =>
      mlxLibraryPath != null ? AppModelId.qwen3Mlx : AppModelId.qwen3;

  // Use llama.cpp (CPU) for the lightweight model on macOS so that the big
  // model can use MLX (GPU) without hitching
  @override
  AppModelId get defaultLightweightModelId => AppModelId.qwen25_3b;

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
