// Rough one-shot benchmark: MLX vs llama.cpp on the same Qwen3 model.
//
// Runs 10 conversational turns with growing context (like the cow app)
// and measures TTFT, reasoning time, response time, and total per turn.
//
// To run:
//   cd packages/cow_e2e
//   dart test test/backend_benchmark_test.dart -r expanded

@TestOn('mac-os')
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:cow_brain/cow_brain.dart';
import 'package:test/test.dart';

import 'helpers.dart';

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

void main() {
  silenceNativeStderr();
  final paths = TestPaths.resolve();

  if (paths.llamaUnavailable || paths.mlxUnavailable) {
    stderr.writeln(
      'Skipping benchmark: both llama and MLX models/libraries required.',
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
      libraryPath: paths.mlxLibraryPath,
      modelServer: modelServer,
    );

    // Load both models.
    final mlxLoaded = await brains.loadModel(
      modelPath: paths.mlxModelPath,
      backend: InferenceBackend.mlx,
      libraryPathOverride: paths.mlxLibraryPath,
    );
    final llamaLoaded = await brains.loadModel(
      modelPath: paths.llamaModelPath,
      modelOptions: const LlamaModelOptions(nGpuLayers: -1, useMmap: true),
      libraryPathOverride: paths.llamaLibraryPath,
    );

    // MLX brain.
    mlxBrain = brains.create('mlx');
    await mlxBrain.init(
      modelHandle: mlxLoaded.modelPointer,
      options: MlxRuntimeOptions(
        modelPath: paths.mlxModelPath,
        libraryPath: paths.mlxLibraryPath,
        contextSize: 10000,
        samplingOptions: defaultSamplingOptions,
      ),
      profile: ModelProfileId.qwen3,
      tools: const [],
      settings: defaultSettings,
      enableReasoning: true,
      systemPrompt: 'You are a helpful assistant.',
    );

    // llama.cpp brain.
    llamaBrain = brains.create('llama');
    await llamaBrain.init(
      modelHandle: llamaLoaded.modelPointer,
      options: LlamaCppRuntimeOptions(
        modelPath: paths.llamaModelPath,
        libraryPath: paths.llamaLibraryPath,
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
        samplingOptions: defaultSamplingOptions,
      ),
      profile: ModelProfileId.qwen3,
      tools: const [],
      settings: defaultSettings,
      enableReasoning: true,
      systemPrompt: 'You are a helpful assistant.',
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
        ..write('  MLX:   ');
      final mlx = await _runTimedTurn(mlxBrain, prompt);
      mlxMetrics.add(mlx);
      stdout
        ..writeln(mlx)
        ..write('  llama: ');
      final llama = await _runTimedTurn(llamaBrain, prompt);
      llamaMetrics.add(llama);
      stdout.writeln(llama);
    }

    _printResults(mlxMetrics, llamaMetrics);

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
    settings: defaultSettings,
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

  final Duration ttft;
  final Duration reasoningEnd;
  final Duration total;

  Duration get reasoning => reasoningEnd - ttft;
  Duration get response => total - reasoningEnd;

  @override
  String toString() =>
      'ttft=${fmtDuration(ttft)}  reasoning=${fmtDuration(reasoning)}  '
      'response=${fmtDuration(response)}  total=${fmtDuration(total)}';
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
        '${fmtDuration(mVal).padLeft(7)} | '
        '${fmtDuration(lVal).padLeft(7)} | '
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
