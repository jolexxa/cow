import 'dart:io';

import 'package:cow_model_manager/src/downloadable_model.dart';
import 'package:path/path.dart' as p;

bool profileFilesPresent(DownloadableModel profile, String modelsDir) {
  for (final file in profile.files) {
    final path = p.join(modelsDir, profile.id, file.fileName);
    if (!File(path).existsSync()) {
      return false;
    }
  }
  return true;
}

bool profilesPresent(Iterable<DownloadableModel> profiles, String modelsDir) {
  for (final profile in profiles) {
    if (!profileFilesPresent(profile, modelsDir)) {
      return false;
    }
  }
  return true;
}
