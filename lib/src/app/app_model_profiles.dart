import 'package:cow/src/app/app_model_profile.dart';
import 'package:cow/src/app/model_runtime_config.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:cow_model_manager/cow_model_manager.dart';

/// Built-in model profile IDs.
enum AppModelId {
  qwen3,
  qwen25,
  qwen25_3b,
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
    modelFamily: LlamaProfileId.qwen3,
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
    modelFamily: LlamaProfileId.qwen25,
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
    modelFamily: LlamaProfileId.qwen25,
    supportsReasoning: false,
    runtimeConfig: const ModelRuntimeConfig(
      contextSize: 2048,
      temperature: 0.3,
    ),
  );

  static AppModelProfile get primaryProfile => qwen3;

  static AppModelProfile get lightweightProfile => qwen25_3b;
}
