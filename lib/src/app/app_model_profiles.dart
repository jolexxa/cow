import 'package:cow_model_manager/cow_model_manager.dart';

final class AppModelProfiles {
  static final ModelProfileSpec qwen3 = ModelProfileSpec(
    id: 'qwen3',
    supportsReasoning: true,
    entrypointFileName: 'Qwen3-8B-Q5_K_M.gguf',
    files: const [
      ModelFileSpec(
        url:
            'https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q5_K_M.gguf',
        fileName: 'Qwen3-8B-Q5_K_M.gguf',
      ),
    ],
  );

  static final ModelProfileSpec qwen25 = ModelProfileSpec(
    id: 'qwen25',
    supportsReasoning: false,
    entrypointFileName: 'qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf',
    files: const [
      ModelFileSpec(
        url:
            'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf',
        fileName: 'qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf',
      ),
      ModelFileSpec(
        url:
            'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf',
        fileName: 'qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf',
      ),
    ],
  );

  static final ModelProfileSpec qwen25_3b = ModelProfileSpec(
    id: 'qwen25_3b',
    supportsReasoning: false,
    entrypointFileName: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
    files: const [
      ModelFileSpec(
        url:
            'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
        fileName: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      ),
    ],
  );

  static ModelProfileSpec get primaryProfile => qwen3;

  static ModelProfileSpec get lightweightProfile => qwen25_3b;
}
