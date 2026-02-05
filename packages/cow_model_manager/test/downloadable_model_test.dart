import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:test/test.dart';

void main() {
  test('DownloadableModel enforces entrypoint in files', () {
    expect(
      () => DownloadableModel(
        id: 'beta',
        files: const [
          DownloadableModelFile(
            url: 'https://example.com/a.bin',
            fileName: 'a.bin',
          ),
        ],
        entrypointFileName: 'missing.bin',
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('DownloadableModelFile and DownloadableModel store values', () {
    const file = DownloadableModelFile(
      url: 'https://example.com/model.bin',
      fileName: 'model.bin',
    );
    final profile = DownloadableModel(
      id: 'gamma',
      files: const [file],
      entrypointFileName: 'model.bin',
    );

    expect(file.url, 'https://example.com/model.bin');
    expect(file.fileName, 'model.bin');
    expect(profile.id, 'gamma');
    expect(profile.files.single.fileName, 'model.bin');
    expect(profile.entrypointFileName, 'model.bin');
  });
}
