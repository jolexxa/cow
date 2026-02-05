import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';

class CowPaths {
  factory CowPaths({String? homeDir, Platform? platform}) {
    final resolvedPlatform = platform ?? const LocalPlatform();
    return CowPaths._(
      homeDir: homeDir ?? _resolveHomeDir(resolvedPlatform),
      platform: resolvedPlatform,
    );
  }

  CowPaths._({required this.homeDir, required this.platform});

  final String homeDir;
  final Platform platform;

  String get cowDir => p.join(homeDir, '.cow');

  String get modelsDir => p.join(cowDir, 'models');

  String get configFile => p.join(cowDir, 'cow.json');

  String modelDir(DownloadableModel profile) => p.join(modelsDir, profile.id);

  String modelFilePath(DownloadableModel profile, DownloadableModelFile file) {
    return p.join(modelDir(profile), file.fileName);
  }

  String modelEntrypoint(DownloadableModel profile) {
    return p.join(modelDir(profile), profile.entrypointFileName);
  }

  static String _resolveHomeDir(Platform platform) {
    final home = platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return home;
    }
    final userProfile = platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }
    throw StateError('Unable to resolve user home directory.');
  }
}
