import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('Llama model option types', () {
    test('LlamaModelOptions defaults are null/false', () {
      const options = LlamaModelOptions();
      expect(options.nGpuLayers, isNull);
      expect(options.mainGpu, isNull);
      expect(options.numa, isNull);
      expect(options.useMmap, isNull);
      expect(options.useMlock, isNull);
      expect(options.checkTensors, isNull);
    });

    test('LlamaContextOptions and sampling options expose fields', () {
      const context = LlamaContextOptions(
        contextSize: 128,
        nBatch: 8,
        nThreads: 4,
        nThreadsBatch: 2,
        useFlashAttn: true,
      );
      const sampling = LlamaSamplingOptions(
        seed: 42,
        topK: 10,
        topP: 0.9,
        minP: 0.05,
        temperature: 0.7,
        typicalP: 0.8,
        penaltyRepeat: 1.1,
        penaltyLastN: 32,
      );

      expect(context.contextSize, 128);
      expect(context.useFlashAttn, isTrue);
      expect(sampling.seed, 42);
      expect(sampling.topK, 10);
      expect(sampling.penaltyLastN, 32);
    });
  });
}
