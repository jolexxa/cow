import 'package:meta/meta.dart';

@immutable
class ModelFileSpec {
  const ModelFileSpec({required this.url, required this.fileName});

  final String url;
  final String fileName;
}

@immutable
class ModelProfileSpec {
  ModelProfileSpec({
    required this.id,
    required this.supportsReasoning,
    required this.files,
    required this.entrypointFileName,
  }) : assert(
         files.any((file) => file.fileName == entrypointFileName),
         'Entrypoint file must be one of the model files.',
       );

  final String id;
  final bool supportsReasoning;
  final List<ModelFileSpec> files;
  final String entrypointFileName;
}
