import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:test/test.dart';

void main() {
  test('returns profiles by id and throws for unknown', () {
    final alpha = ModelProfileSpec(
      id: 'alpha',
      supportsReasoning: false,
      files: const [
        ModelFileSpec(url: 'https://example.com/a', fileName: 'a.bin'),
      ],
      entrypointFileName: 'a.bin',
    );
    final registry = ModelRegistry({'alpha': alpha});

    expect(registry.profiles.single.id, 'alpha');
    expect(registry.profileForId('alpha'), same(alpha));
    expect(() => registry.profileForId('missing'), throwsA(isA<StateError>()));
  });
}
