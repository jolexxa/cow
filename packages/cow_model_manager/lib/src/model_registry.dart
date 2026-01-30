import 'package:cow_model_manager/src/model_specs.dart';

class ModelRegistry {
  ModelRegistry(this._profiles);

  final Map<String, ModelProfileSpec> _profiles;

  Iterable<ModelProfileSpec> get profiles => _profiles.values;

  ModelProfileSpec profileForId(String id) {
    final profile = _profiles[id];
    if (profile == null) {
      throw StateError('Unknown model profile: $id');
    }
    return profile;
  }
}
