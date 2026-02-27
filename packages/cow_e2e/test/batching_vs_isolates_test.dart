// E2E test: batched sequences on one brain vs parallel CPU inference in
// separate isolates.
//
// Compares wall-clock time of running 2 prompts via:
//   1. One brain with 2 sequences (batched decode)
//   2. Two separate brains (separate isolates/contexts) each running 1 prompt
//
// Uses the lightweight qwen25 3B model with CPU-only inference (nGpuLayers: 0)
// so the two isolates genuinely compete for memory bandwidth on separate
// cores, while batching shares the forward pass.
//
// To run:
//   cd packages/cow_e2e
//   dart test test/batching_vs_isolates_test.dart -r expanded

@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:cow_brain/cow_brain.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _prompts = [
  'Explain what a hash table is and how collisions are resolved. Be concise.',
  'Explain what a binary search tree is and its time complexity. Be concise.',
];

const _runs = 5;

void main() {
  silenceNativeStderr();
  final paths = TestPaths.resolve();

  if (paths.llamaCpuUnavailable) {
    stderr.writeln('Skipping: llama CPU model or library not found.');
    return;
  }

  // CPU-only options — forces compute onto cores so isolate parallelism
  // is a real alternative to batching.
  const contextOptions = LlamaContextOptions(
    contextSize: 4096,
    nBatch: 512,
    nThreads: 4,
    nThreadsBatch: 4,
    useFlashAttn: true,
  );
  const modelOptions = LlamaModelOptions(nGpuLayers: 0, useMmap: true);

  test('batching vs parallel isolates ($_runs runs)', () async {
    final modelServer = await ModelServer.spawn();
    final brains = CowBrains<String>(
      libraryPath: paths.llamaLibraryPath,
      modelServer: modelServer,
    );

    final loaded = await brains.loadModel(
      modelPath: paths.llamaCpuModelPath,
      modelOptions: modelOptions,
      libraryPathOverride: paths.llamaLibraryPath,
    );

    // -----------------------------------------------------------------------
    // Helpers to create & init a brain.
    // -----------------------------------------------------------------------
    Future<CowBrain> makeBrain(String key, {int maxSequences = 1}) async {
      final brain = brains.create(key);
      await brain.init(
        modelHandle: loaded.modelPointer,
        options: LlamaCppRuntimeOptions(
          modelPath: paths.llamaCpuModelPath,
          libraryPath: paths.llamaLibraryPath,
          contextOptions: contextOptions,
          modelOptions: modelOptions,
          samplingOptions: defaultSamplingOptions,
          maxSequences: maxSequences,
        ),
        profile: ModelProfileId.qwen25,
        tools: const [],
        settings: defaultSettings,
        enableReasoning: false,
        systemPrompt: 'You are a helpful assistant.',
      );
      return brain;
    }

    final batchedTokPerSec = <double>[];
    final isolateTokPerSec = <double>[];

    for (var run = 0; run < _runs + 1; run++) {
      // -------------------------------------------------------------------
      // Batched: one brain, two sequences.
      // -------------------------------------------------------------------
      final batchedBrain = await makeBrain('batched-$run', maxSequences: 2);
      batchedBrain.createSequence(sequenceId: 1);

      final batchSw = Stopwatch()..start();
      final batchResults = await Future.wait([
        collectTurn(batchedBrain, _prompts[0]),
        collectTurn(batchedBrain, _prompts[1], sequenceId: 1),
      ]);
      batchSw.stop();

      batchedBrain.destroySequence(1);
      await brains.remove('batched-$run');

      // -------------------------------------------------------------------
      // Parallel isolates: two brains, one sequence each.
      // -------------------------------------------------------------------
      final brainA = await makeBrain('iso-a-$run');
      final brainB = await makeBrain('iso-b-$run');

      final isoSw = Stopwatch()..start();
      final isoResults = await Future.wait([
        collectTurn(brainA, _prompts[0]),
        collectTurn(brainB, _prompts[1]),
      ]);
      isoSw.stop();

      await brains.remove('iso-a-$run');
      await brains.remove('iso-b-$run');

      // -------------------------------------------------------------------
      // Report.
      // -------------------------------------------------------------------
      final batchS = batchSw.elapsedMilliseconds / 1000;
      final isoS = isoSw.elapsedMilliseconds / 1000;

      final batchTok = batchResults.fold(0, (s, r) => s + r.tokens);
      final isoTok = isoResults.fold(0, (s, r) => s + r.tokens);

      final batchTps = batchTok / batchS;
      final isoTps = isoTok / isoS;

      if (run == 0) {
        stdout.writeln('\n  warmup (discarded): ');
      } else {
        batchedTokPerSec.add(batchTps);
        isolateTokPerSec.add(isoTps);
        stdout.writeln('  run $run: ');
      }
      stdout.writeln(
        'batched ${batchTps.toStringAsFixed(1)} tok/s '
        '(${batchS.toStringAsFixed(2)}s, $batchTok tok), '
        'isolates ${isoTps.toStringAsFixed(1)} tok/s '
        '(${isoS.toStringAsFixed(2)}s, $isoTok tok)',
      );

      // Sanity: both paths produced output.
      for (final r in [...batchResults, ...isoResults]) {
        expect(r.text, isNotEmpty);
      }
    }

    // Summary.
    final avgBatchTps =
        batchedTokPerSec.reduce((a, b) => a + b) / batchedTokPerSec.length;
    final avgIsoTps =
        isolateTokPerSec.reduce((a, b) => a + b) / isolateTokPerSec.length;

    batchedTokPerSec.sort();
    isolateTokPerSec.sort();
    final medBatchTps = batchedTokPerSec[batchedTokPerSec.length ~/ 2];
    final medIsoTps = isolateTokPerSec[isolateTokPerSec.length ~/ 2];

    stdout
      ..writeln(
        '\n  avg ($_runs runs): '
        'batched ${avgBatchTps.toStringAsFixed(1)} tok/s, '
        'isolates ${avgIsoTps.toStringAsFixed(1)} tok/s, '
        '${(avgBatchTps / avgIsoTps).toStringAsFixed(2)}x',
      )
      ..writeln(
        '  median: '
        'batched ${medBatchTps.toStringAsFixed(1)} tok/s, '
        'isolates ${medIsoTps.toStringAsFixed(1)} tok/s, '
        '${(medBatchTps / medIsoTps).toStringAsFixed(2)}x',
      );

    final winner = medBatchTps >= medIsoTps ? 'BATCHING' : 'ISOLATES';
    final speedup = medBatchTps >= medIsoTps
        ? (medBatchTps / medIsoTps).toStringAsFixed(2)
        : (medIsoTps / medBatchTps).toStringAsFixed(2);
    stdout.writeln('\n  >> $winner wins by ${speedup}x (median tok/s)');

    await brains.dispose();
  });
}
