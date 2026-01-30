import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaProfiles', () {
    test('profileFor returns qwen3 profile', () {
      final profile = LlamaProfiles.profileFor(LlamaProfileId.qwen3);

      expect(profile, same(LlamaProfiles.qwen3));
    });

    test('profileFor returns qwen25 profile', () {
      final profile = LlamaProfiles.profileFor(LlamaProfileId.qwen25);

      expect(profile, same(LlamaProfiles.qwen25));
    });

    test('profileFor returns qwen25 profile for qwen25_3b', () {
      final profile = LlamaProfiles.profileFor(LlamaProfileId.qwen25_3b);

      expect(profile, same(LlamaProfiles.qwen25));
    });
  });
}
