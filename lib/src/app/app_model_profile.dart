import 'package:cow/src/app/model_runtime_config.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:cow_model_manager/cow_model_manager.dart';

class AppModelProfile {
  const AppModelProfile({
    required this.downloadableModel,
    required this.modelFamily,
    required this.supportsReasoning,
    this.runtimeConfig = const ModelRuntimeConfig(),
  });

  final DownloadableModel downloadableModel;
  final LlamaProfileId modelFamily;
  final bool supportsReasoning;
  final ModelRuntimeConfig runtimeConfig;
}
