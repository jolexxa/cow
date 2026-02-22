// Rough one-shot benchmark: MLX vs llama.cpp on the same Qwen3 model.
//
// Runs 10 conversational turns with growing context (like the cow app)
// and measures TTFT, reasoning time, response time, and total per turn.
//
// To run:
//   dart test test/benchmark_test.dart -r expanded
//
// Required env vars (see test.sh):
//   COW_MLX_MODEL_PATH, COW_MLX_LIBRARY_PATH,
//   COW_LLAMA_MODEL_PATH, COW_LLAMA_LIBRARY_PATH

@TestOn('mac-os')
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:cow_brain/cow_brain.dart';
import 'package:test/test.dart';

const _prompts = [
  'What is the Fibonacci sequence? Explain briefly.',
  'Write a short Python function to compute the nth Fibonacci number.',
  'What are the trade-offs between recursion and iteration?',
  'Explain Big O notation in simple terms.',
  'What is a hash table and why is it useful?',
  'Compare quicksort and mergesort.',
  'What is the CAP theorem in distributed systems?',
  'Explain how garbage collection works in modern languages.',
  'What are the SOLID principles in software design?',
  'Summarize everything we discussed in 3 bullet points.',
];

const _settings = AgentSettings(safetyMarginTokens: 64, maxSteps: 8);
const _samplingOptions = SamplingOptions(seed: 42);

void main() {
  final mlxModelPath = Platform.environment['COW_MLX_MODEL_PATH'];
  final mlxLibraryPath = Platform.environment['COW_MLX_LIBRARY_PATH'];
  final llamaModelPath = Platform.environment['COW_LLAMA_MODEL_PATH'];
  final llamaLibraryPath = Platform.environment['COW_LLAMA_LIBRARY_PATH'];

  if (mlxModelPath == null ||
      mlxLibraryPath == null ||
      llamaModelPath == null ||
      llamaLibraryPath == null) {
    stderr.writeln(
      'Skipping benchmark: set COW_MLX_MODEL_PATH, COW_MLX_LIBRARY_PATH, '
      'COW_LLAMA_MODEL_PATH, and COW_LLAMA_LIBRARY_PATH.',
    );
    return;
  }

  late ModelServer modelServer;
  late CowBrains<String> brains;
  late CowBrain mlxBrain;
  late CowBrain llamaBrain;

  setUp(() async {
    modelServer = await ModelServer.spawn();
    brains = CowBrains<String>(
      libraryPath: mlxLibraryPath,
      modelServer: modelServer,
    );

    // Load both models.
    final mlxLoaded = await brains.loadModel(
      modelPath: mlxModelPath,
      backend: InferenceBackend.mlx,
      libraryPathOverride: mlxLibraryPath,
    );
    final llamaLoaded = await brains.loadModel(
      modelPath: llamaModelPath,
      modelOptions: const LlamaModelOptions(nGpuLayers: -1, useMmap: true),
      libraryPathOverride: llamaLibraryPath,
    );

    // MLX brain.
    mlxBrain = brains.create('mlx');
    await mlxBrain.init(
      modelHandle: mlxLoaded.modelPointer,
      options: MlxRuntimeOptions(
        modelPath: mlxModelPath,
        libraryPath: mlxLibraryPath,
        contextSize: 10000,
        samplingOptions: _samplingOptions,
      ),
      profile: ModelProfileId.qwen3,
      tools: const [],
      settings: _settings,
      enableReasoning: true,
    );

    // llama.cpp brain.
    llamaBrain = brains.create('llama');
    await llamaBrain.init(
      modelHandle: llamaLoaded.modelPointer,
      options: LlamaCppRuntimeOptions(
        modelPath: llamaModelPath,
        libraryPath: llamaLibraryPath,
        contextOptions: const LlamaContextOptions(
          contextSize: 10000,
          nBatch: 512,
          nThreads: 4,
          nThreadsBatch: 4,
          useFlashAttn: true,
        ),
        modelOptions: const LlamaModelOptions(
          nGpuLayers: -1,
          useMmap: true,
        ),
        samplingOptions: _samplingOptions,
      ),
      profile: ModelProfileId.qwen3,
      tools: const [],
      settings: _settings,
      enableReasoning: true,
    );
  });

  tearDown(() async {
    await brains.dispose();
  });

  test('benchmark: MLX vs llama.cpp — 10 turns', () async {
    final mlxMetrics = <_TurnMetrics>[];
    final llamaMetrics = <_TurnMetrics>[];

    for (var i = 0; i < _prompts.length; i++) {
      final prompt = _prompts[i];
      stdout
        ..writeln('\n--- Turn ${i + 1}: $prompt ---')
        // MLX first.
        ..write('  MLX:   ');
      final mlx = await _runTimedTurn(mlxBrain, prompt);
      mlxMetrics.add(mlx);
      stdout
        ..writeln(mlx)
        // llama.cpp second (sequential to avoid GPU contention).
        ..write('  llama: ');
      final llama = await _runTimedTurn(llamaBrain, prompt);
      llamaMetrics.add(llama);
      stdout.writeln(llama);
    }

    // Print results table.
    _printResults(mlxMetrics, llamaMetrics);

    // Just ensure both completed all 10 turns.
    expect(mlxMetrics, hasLength(_prompts.length));
    expect(llamaMetrics, hasLength(_prompts.length));
  });
}

// ---------------------------------------------------------------------------
// Timing
// ---------------------------------------------------------------------------

Future<_TurnMetrics> _runTimedTurn(CowBrain brain, String prompt) async {
  final sw = Stopwatch()..start();
  Duration? ttft;
  Duration? reasoningEnd;
  Duration? responseEnd;
  var gotReasoning = false;
  var gotText = false;

  await for (final event in brain.runTurn(
    userMessage: Message(role: Role.user, content: prompt),
    settings: _settings,
    enableReasoning: true,
  )) {
    if (!gotReasoning &&
        !gotText &&
        (event is AgentReasoningDelta || event is AgentTextDelta)) {
      ttft = sw.elapsed;
    }
    if (!gotReasoning && event is AgentReasoningDelta) {
      gotReasoning = true;
    }
    if (!gotText && event is AgentTextDelta) {
      reasoningEnd = sw.elapsed;
      gotText = true;
    }
    if (event is AgentTurnFinished) {
      responseEnd = sw.elapsed;
    }
  }
  sw.stop();

  return _TurnMetrics(
    ttft: ttft ?? sw.elapsed,
    reasoningEnd: reasoningEnd ?? sw.elapsed,
    total: responseEnd ?? sw.elapsed,
  );
}

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

class _TurnMetrics {
  _TurnMetrics({
    required this.ttft,
    required this.reasoningEnd,
    required this.total,
  });

  /// Time to first token (reasoning or text).
  final Duration ttft;

  /// Timestamp when first text delta arrived (end of reasoning phase).
  final Duration reasoningEnd;

  /// Total turn time.
  final Duration total;

  /// Reasoning duration = reasoningEnd - ttft.
  Duration get reasoning => reasoningEnd - ttft;

  /// Response duration = total - reasoningEnd.
  Duration get response => total - reasoningEnd;

  @override
  String toString() =>
      'ttft=${_fmt(ttft)}  reasoning=${_fmt(reasoning)}  '
      'response=${_fmt(response)}  total=${_fmt(total)}';
}

String _fmt(Duration d) {
  final ms = d.inMilliseconds;
  return '${(ms / 1000).toStringAsFixed(2)}s';
}

// ---------------------------------------------------------------------------
// Results table
// ---------------------------------------------------------------------------

void _printResults(List<_TurnMetrics> mlx, List<_TurnMetrics> llama) {
  const metricNames = ['TTFT', 'Reasoning', 'Response', 'Total'];
  var mlxWins = 0;
  var llamaWins = 0;

  Duration metricValue(_TurnMetrics m, String metric) => switch (metric) {
    'TTFT' => m.ttft,
    'Reasoning' => m.reasoning,
    'Response' => m.response,
    'Total' => m.total,
    _ => Duration.zero,
  };

  stdout
    ..writeln('\n')
    ..writeln(
      '====================================================================',
    )
    ..writeln(' Turn | Metric      |     MLX |   llama | Winner')
    ..writeln(
      '====================================================================',
    );

  for (var i = 0; i < mlx.length; i++) {
    for (final metric in metricNames) {
      final mVal = metricValue(mlx[i], metric);
      final lVal = metricValue(llama[i], metric);
      final winner = mVal < lVal
          ? 'MLX'
          : lVal < mVal
          ? 'llama'
          : 'tie';
      if (mVal < lVal) mlxWins++;
      if (lVal < mVal) llamaWins++;

      stdout.writeln(
        '  ${(i + 1).toString().padLeft(3)} | '
        '${metric.padRight(11)} | '
        '${_fmt(mVal).padLeft(7)} | '
        '${_fmt(lVal).padLeft(7)} | '
        '$winner',
      );
    }
    if (i < mlx.length - 1) {
      stdout.writeln('------+-------------+---------+---------+--------');
    }
  }

  // Averages.
  stdout.writeln(
    '====================================================================',
  );

  for (final metric in metricNames) {
    final mAvg = _avgMs(mlx.map((m) => metricValue(m, metric)));
    final lAvg = _avgMs(llama.map((m) => metricValue(m, metric)));
    final winner = mAvg < lAvg
        ? 'MLX'
        : lAvg < mAvg
        ? 'llama'
        : 'tie';
    if (mAvg < lAvg) mlxWins++;
    if (lAvg < mAvg) llamaWins++;

    stdout.writeln(
      '  AVG | '
      '${metric.padRight(11)} | '
      '${_fmtMs(mAvg).padLeft(7)} | '
      '${_fmtMs(lAvg).padLeft(7)} | '
      '$winner',
    );
  }

  stdout.writeln(
    '====================================================================',
  );

  final overall = mlxWins > llamaWins
      ? 'MLX'
      : llamaWins > mlxWins
      ? 'llama'
      : 'tie';
  stdout.writeln(
    '\nOverall winner: $overall '
    '(MLX $mlxWins wins, llama $llamaWins wins)',
  );
}

double _avgMs(Iterable<Duration> durations) {
  if (durations.isEmpty) return 0;
  final total = durations.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
  return total / durations.length;
}

String _fmtMs(double ms) => '${(ms / 1000).toStringAsFixed(2)}s';
