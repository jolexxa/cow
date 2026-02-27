// Shared helpers for cow_e2e tests.

import 'dart:io';

import 'package:cow/cow.dart' show OSPlatform, redirectNativeStderr;
import 'package:cow_brain/cow_brain.dart';

// ---------------------------------------------------------------------------
// Path resolution — replaces test.sh
// ---------------------------------------------------------------------------

/// Resolved paths for e2e tests. Checks env vars first, falls back to
/// conventional locations relative to the repo root.
class TestPaths {
  TestPaths._({
    required this.repoRoot,
    required this.llamaModelPath,
    required this.llamaCpuModelPath,
    required this.llamaLibraryPath,
    required this.mlxModelPath,
    required this.mlxSummaryModelPath,
    required this.mlxLibraryPath,
  });

  factory TestPaths.resolve() {
    final repoRoot = _findRepoRoot();
    final home = Platform.environment['HOME'] ?? '';

    final llamaLib = Platform.isMacOS
        ? '$repoRoot/packages/llama_cpp_dart/assets/native/macos/arm64/'
              'libllama.0.dylib'
        : '$repoRoot/packages/llama_cpp_dart/assets/native/linux/x64/'
              'libllama.so.0';

    return TestPaths._(
      repoRoot: repoRoot,
      llamaModelPath:
          _env('COW_LLAMA_MODEL_PATH') ??
          '$home/.cow/models/qwen3/Qwen3-8B-Q5_K_M.gguf',
      llamaCpuModelPath:
          _env('COW_LLAMA_CPU_MODEL_PATH') ??
          '$home/.cow/models/qwen25_3b/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      llamaLibraryPath: _env('COW_LLAMA_LIBRARY_PATH') ?? llamaLib,
      mlxModelPath: _env('COW_MLX_MODEL_PATH') ?? '$home/.cow/models/qwen3Mlx',
      mlxSummaryModelPath:
          _env('COW_MLX_SUMMARY_MODEL_PATH') ??
          '$home/.cow/models/qwen25_3bMlx',
      mlxLibraryPath:
          _env('COW_MLX_LIBRARY_PATH') ??
          '$repoRoot/packages/cow_mlx/.build/release/libCowMLX.dylib',
    );
  }

  final String repoRoot;

  // llama.cpp
  final String llamaModelPath;
  final String llamaCpuModelPath;
  final String llamaLibraryPath;

  // MLX (macOS only)
  final String mlxModelPath;
  final String mlxSummaryModelPath;
  final String mlxLibraryPath;

  /// True when llama.cpp model + library are missing from disk.
  bool get llamaUnavailable =>
      !File(llamaModelPath).existsSync() ||
      !File(llamaLibraryPath).existsSync();

  /// True when the lightweight CPU model is missing.
  bool get llamaCpuUnavailable =>
      !File(llamaCpuModelPath).existsSync() ||
      !File(llamaLibraryPath).existsSync();

  /// True when MLX model + library are missing from disk.
  bool get mlxUnavailable =>
      !Platform.isMacOS ||
      !Directory(mlxModelPath).existsSync() ||
      !File(mlxLibraryPath).existsSync();

  /// True when MLX summary model is missing from disk.
  bool get mlxSummaryUnavailable =>
      mlxUnavailable || !Directory(mlxSummaryModelPath).existsSync();

  /// Walks up from cwd to find the repo root (directory containing packages/).
  static String _findRepoRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 10; i++) {
      if (Directory('${dir.path}/packages').existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break; // filesystem root
      dir = parent;
    }
    // Fallback: assume we're in packages/cow_e2e.
    return Directory(
      '${Directory.current.path}/../..',
    ).resolveSymbolicLinksSync();
  }

  static String? _env(String key) {
    final v = Platform.environment[key];
    return (v != null && v.isNotEmpty) ? v : null;
  }
}

// ---------------------------------------------------------------------------
// Common constants
// ---------------------------------------------------------------------------

const defaultSettings = AgentSettings(safetyMarginTokens: 64, maxSteps: 8);
const defaultSamplingOptions = SamplingOptions(seed: 42);

// ---------------------------------------------------------------------------
// Turn collection
// ---------------------------------------------------------------------------

typedef TurnResult = ({String text, int tokens});

/// Runs a single turn and collects the full text + token count.
Future<TurnResult> collectTurn(
  CowBrain brain,
  String prompt, {
  AgentSettings settings = defaultSettings,
  int sequenceId = 0,
}) async {
  final buf = StringBuffer();
  var tokens = 0;
  int? firstRemaining;
  int? lastRemaining;

  await for (final event in brain.runTurn(
    userMessage: Message(role: Role.user, content: prompt),
    settings: settings,
    enableReasoning: false,
    sequenceId: sequenceId,
  )) {
    if (event is AgentTextDelta) {
      buf.write(event.text);
    } else if (event is AgentTelemetryUpdate) {
      firstRemaining ??= event.remainingTokens;
      lastRemaining = event.remainingTokens;
    }
  }

  if (firstRemaining != null && lastRemaining != null) {
    tokens = firstRemaining - lastRemaining;
  }

  return (text: buf.toString(), tokens: tokens);
}

String fmtDuration(Duration d) =>
    '${(d.inMilliseconds / 1000).toStringAsFixed(2)}s';

// ---------------------------------------------------------------------------
// Silence native output (llama.cpp stderr spam)
// ---------------------------------------------------------------------------

/// Redirects native stderr to `/dev/null` so llama.cpp log spam doesn't
/// pollute test output. Call once at the top of `main()`.
void silenceNativeStderr() {
  redirectNativeStderr(OSPlatform.current());
}
