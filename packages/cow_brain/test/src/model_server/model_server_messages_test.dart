import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/model_server/model_server_messages.dart';
import 'package:test/test.dart';

void main() {
  group('ModelServerRequest', () {
    test('LoadModelRequest roundtrips through JSON', () {
      const request = LoadModelRequest(
        modelPath: '/models/qwen.gguf',
        libraryPath: '/lib/libllama.so',
        modelOptions: LlamaModelOptions(nGpuLayers: 32),
      );

      final json = request.toJson();
      final decoded = ModelServerRequest.fromJson(json);

      expect(decoded, isA<LoadModelRequest>());
      final loadModel = decoded as LoadModelRequest;
      expect(loadModel.modelPath, '/models/qwen.gguf');
      expect(loadModel.libraryPath, '/lib/libllama.so');
      expect(loadModel.modelOptions.nGpuLayers, 32);
    });

    test('UnloadModelRequest roundtrips through JSON', () {
      const request = UnloadModelRequest(modelPath: '/models/qwen.gguf');

      final json = request.toJson();
      final decoded = ModelServerRequest.fromJson(json);

      expect(decoded, isA<UnloadModelRequest>());
      final unloadModel = decoded as UnloadModelRequest;
      expect(unloadModel.modelPath, '/models/qwen.gguf');
    });

    test('DisposeModelServerRequest roundtrips through JSON', () {
      const request = DisposeModelServerRequest();

      final json = request.toJson();
      final decoded = ModelServerRequest.fromJson(json);

      expect(decoded, isA<DisposeModelServerRequest>());
    });
  });

  group('ModelServerResponse', () {
    test('ModelLoadedResponse roundtrips through JSON', () {
      const response = ModelLoadedResponse(
        modelPath: '/models/qwen.gguf',
        modelPointer: 12345678,
      );

      final json = response.toJson();
      final decoded = ModelServerResponse.fromJson(json);

      expect(decoded, isA<ModelLoadedResponse>());
      final modelLoaded = decoded as ModelLoadedResponse;
      expect(modelLoaded.modelPath, '/models/qwen.gguf');
      expect(modelLoaded.modelPointer, 12345678);
    });

    test('ModelUnloadedResponse roundtrips through JSON', () {
      const response = ModelUnloadedResponse(modelPath: '/models/qwen.gguf');

      final json = response.toJson();
      final decoded = ModelServerResponse.fromJson(json);

      expect(decoded, isA<ModelUnloadedResponse>());
      final modelUnloaded = decoded as ModelUnloadedResponse;
      expect(modelUnloaded.modelPath, '/models/qwen.gguf');
    });

    test('LoadProgressResponse roundtrips through JSON', () {
      const response = LoadProgressResponse(
        modelPath: '/models/qwen.gguf',
        progress: 0.75,
      );

      final json = response.toJson();
      final decoded = ModelServerResponse.fromJson(json);

      expect(decoded, isA<LoadProgressResponse>());
      final loadProgress = decoded as LoadProgressResponse;
      expect(loadProgress.modelPath, '/models/qwen.gguf');
      expect(loadProgress.progress, 0.75);
    });

    test('ModelServerError roundtrips through JSON', () {
      const response = ModelServerError(error: 'Failed to load model');

      final json = response.toJson();
      final decoded = ModelServerResponse.fromJson(json);

      expect(decoded, isA<ModelServerError>());
      final error = decoded as ModelServerError;
      expect(error.error, 'Failed to load model');
    });
  });

  group('LoadModelRequest', () {
    test('uses default model options when not specified', () {
      final json = {
        'type': 'load_model',
        'modelPath': '/models/test.gguf',
        'libraryPath': '/lib/libllama.so',
      };

      final request = LoadModelRequest.fromJson(json);

      expect(request.modelOptions.nGpuLayers, isNull);
    });
  });
}
