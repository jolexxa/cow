import 'package:cow_model_manager/src/downloadable_model.dart';

class ModelRegistry {
  ModelRegistry(this._profiles);

  final Map<String, DownloadableModel> _profiles;

  Iterable<DownloadableModel> get profiles => _profiles.values;

  DownloadableModel profileForId(String id) {
    final profile = _profiles[id];
    if (profile == null) {
      throw StateError('Unknown model profile: $id');
    }
    return profile;
  }
}
