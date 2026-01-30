import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:test/test.dart';

void main() {
  test('ModelProfileSpec enforces entrypoint in files', () {
    expect(
      () => ModelProfileSpec(
        id: 'beta',
        supportsReasoning: true,
        files: const [
          ModelFileSpec(url: 'https://example.com/a.bin', fileName: 'a.bin'),
        ],
        entrypointFileName: 'missing.bin',
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('ModelFileSpec and ModelProfileSpec store values', () {
    const file = ModelFileSpec(
      url: 'https://example.com/model.bin',
      fileName: 'model.bin',
    );
    final profile = ModelProfileSpec(
      id: 'gamma',
      supportsReasoning: false,
      files: const [file],
      entrypointFileName: 'model.bin',
    );

    expect(file.url, 'https://example.com/model.bin');
    expect(file.fileName, 'model.bin');
    expect(profile.id, 'gamma');
    expect(profile.supportsReasoning, isFalse);
    expect(profile.files.single.fileName, 'model.bin');
    expect(profile.entrypointFileName, 'model.bin');
  });
}
