import 'dart:io';

import 'package:cow_model_manager/src/cow_paths.dart';
import 'package:cow_model_manager/src/model_specs.dart';

bool profileFilesPresent(ModelProfileSpec profile, CowPaths paths) {
  for (final file in profile.files) {
    final path = paths.modelFilePath(profile, file);
    if (!File(path).existsSync()) {
      return false;
    }
  }
  return true;
}

bool profilesPresent(Iterable<ModelProfileSpec> profiles, CowPaths paths) {
  for (final profile in profiles) {
    if (!profileFilesPresent(profile, paths)) {
      return false;
    }
  }
  return true;
}
