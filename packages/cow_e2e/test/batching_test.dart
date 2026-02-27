// E2E batching tests: verify concurrent sequences on a single brain.
//
// Tests both MLX and llama.cpp backends with multiple sequences running
// concurrently on the same brain, including forked sequences.
//
// To run:
//   cd packages/cow_e2e
//   dart test test/batching_test.dart -r expanded

@TestOn('mac-os')
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:cow_brain/cow_brain.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _prompts = [
  'What is 2+2? Answer in one word.',
  'Name three colors. Be brief.',
  'What is the capital of France? One word.',
];

void main() {
  silenceNativeStderr();
  final paths = TestPaths.resolve();

  // ---------------------------------------------------------------------------
  // llama.cpp
  // ---------------------------------------------------------------------------

  group(
    'llama.cpp batching',
    skip: paths.llamaUnavailable ? 'llama model/library not found' : null,
    () {
      late ModelServer modelServer;
      late CowBrains<String> brains;
      late CowBrain brain;

      setUp(() async {
        modelServer = await ModelServer.spawn();
        brains = CowBrains<String>(
          libraryPath: paths.llamaLibraryPath,
          modelServer: modelServer,
        );

        final loaded = await brains.loadModel(
          modelPath: paths.llamaModelPath,
          modelOptions: const LlamaModelOptions(
            nGpuLayers: -1,
            useMmap: true,
          ),
          libraryPathOverride: paths.llamaLibraryPath,
        );

        brain = brains.create('llama');
        await brain.init(
          modelHandle: loaded.modelPointer,
          options: LlamaCppRuntimeOptions(
            modelPath: paths.llamaModelPath,
            libraryPath: paths.llamaLibraryPath,
            contextOptions: const LlamaContextOptions(
              contextSize: 8192,
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
            maxSequences: 4,
          ),
          profile: ModelProfileId.qwen3,
          tools: const [],
          settings: defaultSettings,
          enableReasoning: false,
          systemPrompt: 'You are a helpful assistant.',
        );
      });

      tearDown(() async {
        await brains.dispose();
      });

      test('3 concurrent sequences', () async {
        brain
          ..createSequence(sequenceId: 1)
          ..createSequence(sequenceId: 2);

        final sw = Stopwatch()..start();
        final results = await Future.wait([
          collectTurn(brain, _prompts[0]),
          collectTurn(brain, _prompts[1], sequenceId: 1),
          collectTurn(brain, _prompts[2], sequenceId: 2),
        ]);
        sw.stop();

        stdout.writeln(
          '\n  llama.cpp — 3 concurrent sequences: '
          '${fmtDuration(sw.elapsed)}',
        );

        for (var i = 0; i < results.length; i++) {
          final text = results[i].text;
          stdout.writeln('    seq $i: ${text.replaceAll('\n', ' ').trim()}');
          expect(text, isNotEmpty, reason: 'Sequence $i produced no text');
        }

        brain
          ..destroySequence(1)
          ..destroySequence(2);
      });

      test('forked sequence shares prefix', () async {
        final prefix = await collectTurn(
          brain,
          'Remember: the secret word is "banana". Acknowledge briefly.',
        );
        stdout.writeln(
          '\n  llama.cpp fork — prefix: '
          '${prefix.text.replaceAll('\n', ' ').trim()}',
        );
        expect(prefix.text, isNotEmpty);

        brain.createSequence(sequenceId: 1, forkFrom: 0);

        final results = await Future.wait([
          collectTurn(brain, 'What was the secret word?'),
          collectTurn(brain, 'What was the secret word?', sequenceId: 1),
        ]);

        for (var i = 0; i < results.length; i++) {
          stdout.writeln(
            '    seq $i: ${results[i].text.replaceAll('\n', ' ').trim()}',
          );
          expect(
            results[i].text,
            isNotEmpty,
            reason: 'Forked sequence $i produced no text',
          );
        }

        brain.destroySequence(1);
      });

      test('sequential vs concurrent throughput', () async {
        final seqSw = Stopwatch()..start();
        for (final prompt in _prompts) {
          await collectTurn(brain, prompt);
        }
        seqSw.stop();

        brain
          ..createSequence(sequenceId: 1)
          ..createSequence(sequenceId: 2);

        final concSw = Stopwatch()..start();
        await Future.wait([
          collectTurn(brain, _prompts[0]),
          collectTurn(brain, _prompts[1], sequenceId: 1),
          collectTurn(brain, _prompts[2], sequenceId: 2),
        ]);
        concSw.stop();

        final speedup = seqSw.elapsedMilliseconds / concSw.elapsedMilliseconds;

        stdout.writeln(
          '\n  llama.cpp — sequential: ${fmtDuration(seqSw.elapsed)}, '
          'concurrent: ${fmtDuration(concSw.elapsed)}, '
          'speedup: ${speedup.toStringAsFixed(2)}x',
        );

        brain
          ..destroySequence(1)
          ..destroySequence(2);
      });
    },
  );

  // ---------------------------------------------------------------------------
  // MLX
  // ---------------------------------------------------------------------------

  group(
    'MLX batching',
    skip: paths.mlxUnavailable ? 'MLX model/library not found' : null,
    () {
      late ModelServer modelServer;
      late CowBrains<String> brains;
      late CowBrain brain;

      setUp(() async {
        modelServer = await ModelServer.spawn();
        brains = CowBrains<String>(
          libraryPath: paths.mlxLibraryPath,
          modelServer: modelServer,
        );

        final loaded = await brains.loadModel(
          modelPath: paths.mlxModelPath,
          backend: InferenceBackend.mlx,
          libraryPathOverride: paths.mlxLibraryPath,
        );

        brain = brains.create('mlx');
        await brain.init(
          modelHandle: loaded.modelPointer,
          options: MlxRuntimeOptions(
            modelPath: paths.mlxModelPath,
            libraryPath: paths.mlxLibraryPath,
            contextSize: 8192,
            samplingOptions: defaultSamplingOptions,
            maxSequences: 4,
          ),
          profile: ModelProfileId.qwen3,
          tools: const [],
          settings: defaultSettings,
          enableReasoning: false,
          systemPrompt: 'You are a helpful assistant.',
        );
      });

      tearDown(() async {
        await brains.dispose();
      });

      test('3 concurrent sequences', () async {
        brain
          ..createSequence(sequenceId: 1)
          ..createSequence(sequenceId: 2);

        final sw = Stopwatch()..start();
        final results = await Future.wait([
          collectTurn(brain, _prompts[0]),
          collectTurn(brain, _prompts[1], sequenceId: 1),
          collectTurn(brain, _prompts[2], sequenceId: 2),
        ]);
        sw.stop();

        stdout.writeln(
          '\n  MLX — 3 concurrent sequences: ${fmtDuration(sw.elapsed)}',
        );

        for (var i = 0; i < results.length; i++) {
          final text = results[i].text;
          stdout.writeln('    seq $i: ${text.replaceAll('\n', ' ').trim()}');
          expect(text, isNotEmpty, reason: 'Sequence $i produced no text');
        }

        brain
          ..destroySequence(1)
          ..destroySequence(2);
      });

      test('forked sequence shares prefix', () async {
        final prefix = await collectTurn(
          brain,
          'Remember: the secret word is "banana". Acknowledge briefly.',
        );
        stdout.writeln(
          '\n  MLX fork — prefix: '
          '${prefix.text.replaceAll('\n', ' ').trim()}',
        );
        expect(prefix.text, isNotEmpty);

        brain.createSequence(sequenceId: 1, forkFrom: 0);

        final results = await Future.wait([
          collectTurn(brain, 'What was the secret word?'),
          collectTurn(brain, 'What was the secret word?', sequenceId: 1),
        ]);

        for (var i = 0; i < results.length; i++) {
          stdout.writeln(
            '    seq $i: ${results[i].text.replaceAll('\n', ' ').trim()}',
          );
          expect(
            results[i].text,
            isNotEmpty,
            reason: 'Forked sequence $i produced no text',
          );
        }

        brain.destroySequence(1);
      });

      test('sequential vs concurrent throughput', () async {
        final seqSw = Stopwatch()..start();
        for (final prompt in _prompts) {
          await collectTurn(brain, prompt);
        }
        seqSw.stop();

        brain
          ..createSequence(sequenceId: 1)
          ..createSequence(sequenceId: 2);

        final concSw = Stopwatch()..start();
        await Future.wait([
          collectTurn(brain, _prompts[0]),
          collectTurn(brain, _prompts[1], sequenceId: 1),
          collectTurn(brain, _prompts[2], sequenceId: 2),
        ]);
        concSw.stop();

        final speedup = seqSw.elapsedMilliseconds / concSw.elapsedMilliseconds;

        stdout.writeln(
          '\n  MLX — sequential: ${fmtDuration(seqSw.elapsed)}, '
          'concurrent: ${fmtDuration(concSw.elapsed)}, '
          'speedup: ${speedup.toStringAsFixed(02)}x',
        );

        brain
          ..destroySequence(1)
          ..destroySequence(2);
      });
    },
  );
}
