import 'package:cow_brain/src/adapters/model_profiles.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('ModelProfiles', () {
    test('profileFor returns qwen3 profile', () {
      final profile = ModelProfiles.profileFor(ModelProfileId.qwen3);

      expect(profile, same(ModelProfiles.qwen3));
    });

    test('profileFor returns qwen25 profile', () {
      final profile = ModelProfiles.profileFor(ModelProfileId.qwen25);

      expect(profile, same(ModelProfiles.qwen25));
    });

    test('profileFor throws for auto', () {
      expect(
        () => ModelProfiles.profileFor(ModelProfileId.auto),
        throwsArgumentError,
      );
    });
  });
}
