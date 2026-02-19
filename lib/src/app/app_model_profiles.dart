import 'package:cow/src/app/app_model_profile.dart';
import 'package:cow/src/app/model_runtime_config.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:cow_model_manager/cow_model_manager.dart';

/// Built-in model profile IDs.
enum AppModelId {
  qwen3,
  qwen25,
  qwen25_3b,
  qwen3Mlx,
}

final class AppModelProfiles {
  static final AppModelProfile qwen3 = AppModelProfile(
    downloadableModel: DownloadableModel(
      id: AppModelId.qwen3.name,
      entrypointFileName: 'Qwen3-8B-Q5_K_M.gguf',
      files: const [
        DownloadableModelFile(
          url:
              'https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q5_K_M.gguf',
          fileName: 'Qwen3-8B-Q5_K_M.gguf',
        ),
      ],
    ),
    modelFamily: ModelProfileId.qwen3,
    supportsReasoning: true,
    runtimeConfig: const ModelRuntimeConfig(contextSize: 10000),
  );

  static final AppModelProfile qwen25 = AppModelProfile(
    downloadableModel: DownloadableModel(
      id: AppModelId.qwen25.name,
      entrypointFileName: 'qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf',
      files: const [
        DownloadableModelFile(
          url:
              'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf',
          fileName: 'qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf',
        ),
        DownloadableModelFile(
          url:
              'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf',
          fileName: 'qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf',
        ),
      ],
    ),
    modelFamily: ModelProfileId.qwen25,
    supportsReasoning: false,
    runtimeConfig: const ModelRuntimeConfig(contextSize: 10000),
  );

  static final AppModelProfile qwen25_3b = AppModelProfile(
    downloadableModel: DownloadableModel(
      id: AppModelId.qwen25_3b.name,
      entrypointFileName: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      files: const [
        DownloadableModelFile(
          url:
              'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
          fileName: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
        ),
      ],
    ),
    modelFamily: ModelProfileId.qwen25,
    supportsReasoning: false,
    runtimeConfig: const ModelRuntimeConfig(
      contextSize: 2048,
      temperature: 0.3,
    ),
  );

  /// Qwen3-8B for MLX (Apple Silicon native).
  static final AppModelProfile qwen3Mlx = AppModelProfile(
    downloadableModel: DownloadableModel(
      id: AppModelId.qwen3Mlx.name,
      entrypointFileName: 'config.json',
      files: const [
        // MLX models are directories — the model manager downloads
        // individual files into the model directory.
        DownloadableModelFile(
          url:
              'https://huggingface.co/mlx-community/Qwen3-8B-4bit/resolve/main/config.json',
          fileName: 'config.json',
        ),
        DownloadableModelFile(
          url:
              'https://huggingface.co/mlx-community/Qwen3-8B-4bit/resolve/main/model.safetensors',
          fileName: 'model.safetensors',
        ),
        DownloadableModelFile(
          url:
              'https://huggingface.co/mlx-community/Qwen3-8B-4bit/resolve/main/tokenizer.json',
          fileName: 'tokenizer.json',
        ),
        DownloadableModelFile(
          url:
              'https://huggingface.co/mlx-community/Qwen3-8B-4bit/resolve/main/tokenizer_config.json',
          fileName: 'tokenizer_config.json',
        ),
        DownloadableModelFile(
          url:
              'https://huggingface.co/mlx-community/Qwen3-8B-4bit/resolve/main/special_tokens_map.json',
          fileName: 'special_tokens_map.json',
        ),
      ],
    ),
    modelFamily: ModelProfileId.qwen3,
    supportsReasoning: true,
    runtimeConfig: const ModelRuntimeConfig(contextSize: 10000),
    backend: InferenceBackend.mlx,
  );

  static AppModelProfile get primaryProfile => qwen3;

  static AppModelProfile get lightweightProfile => qwen25_3b;
}
