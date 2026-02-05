import 'package:meta/meta.dart';

@immutable
class DownloadableModelFile {
  const DownloadableModelFile({required this.url, required this.fileName});

  final String url;
  final String fileName;
}

@immutable
class DownloadableModel {
  DownloadableModel({
    required this.id,
    required this.files,
    required this.entrypointFileName,
  }) : assert(
         files.any((file) => file.fileName == entrypointFileName),
         'Entrypoint file must be one of the model files.',
       );

  final String id;
  final List<DownloadableModelFile> files;
  final String entrypointFileName;
}
