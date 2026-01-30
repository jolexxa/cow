import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:test/test.dart';

void main() {
  test('ModelInstallController cancels', () {
    final controller = ModelInstallController();
    expect(controller.cancelled, isFalse);

    controller.cancel();
    expect(controller.cancelled, isTrue);
  });

  test('ModelInstallCancelled has friendly message', () {
    expect(
      const ModelInstallCancelled().toString(),
      'Model installation cancelled.',
    );
  });

  test('ModelInstallProgress stores values', () {
    const file = ModelFileSpec(url: 'https://example.com/a', fileName: 'a.bin');
    final profile = ModelProfileSpec(
      id: 'alpha',
      supportsReasoning: true,
      files: const [file],
      entrypointFileName: 'a.bin',
    );

    final progress = ModelInstallProgress(
      profile: profile,
      file: file,
      fileReceivedBytes: 10,
      fileTotalBytes: 20,
      totalReceivedBytes: 30,
      totalBytes: 40,
      speedBytesPerSecond: 50,
      fileCompleted: true,
      fileSkipped: false,
    );

    expect(progress.profile, same(profile));
    expect(progress.file, same(file));
    expect(progress.fileReceivedBytes, 10);
    expect(progress.fileTotalBytes, 20);
    expect(progress.totalReceivedBytes, 30);
    expect(progress.totalBytes, 40);
    expect(progress.speedBytesPerSecond, 50);
    expect(progress.fileCompleted, isTrue);
    expect(progress.fileSkipped, isFalse);
  });
}
