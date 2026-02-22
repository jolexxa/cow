part of 'os_platform.dart';

class Linux extends OSPlatform {
  const Linux();

  @override
  AppModelId get defaultPrimaryModelId => AppModelId.qwen3;

  @override
  AppModelId get defaultLightweightModelId => AppModelId.qwen25_3b;

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
