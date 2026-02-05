import 'dart:io';

import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('profileFilesPresent returns true only when all files exist', () async {
    final tempDir = await Directory.systemTemp.createTemp('cow-presence-');
    try {
      final profile = DownloadableModel(
        id: 'presence',

        files: const [
          DownloadableModelFile(
            url: 'https://example.com/a',
            fileName: 'a.bin',
          ),
          DownloadableModelFile(
            url: 'https://example.com/b',
            fileName: 'b.bin',
          ),
        ],
        entrypointFileName: 'a.bin',
      );
      final modelsDir = p.join(tempDir.path, '.cow', 'models');

      Directory(p.join(modelsDir, profile.id)).createSync(recursive: true);
      File(p.join(modelsDir, profile.id, 'a.bin')).writeAsBytesSync([1, 2]);
      File(p.join(modelsDir, profile.id, 'b.bin')).writeAsBytesSync([3, 4]);

      expect(profileFilesPresent(profile, modelsDir), isTrue);

      File(p.join(modelsDir, profile.id, 'b.bin')).deleteSync();
      expect(profileFilesPresent(profile, modelsDir), isFalse);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'profilesPresent returns true only when all profiles are present',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('cow-profiles-');
      try {
        final profileA = DownloadableModel(
          id: 'a',

          files: const [
            DownloadableModelFile(
              url: 'https://example.com/a',
              fileName: 'a.bin',
            ),
          ],
          entrypointFileName: 'a.bin',
        );
        final profileB = DownloadableModel(
          id: 'b',

          files: const [
            DownloadableModelFile(
              url: 'https://example.com/b',
              fileName: 'b.bin',
            ),
          ],
          entrypointFileName: 'b.bin',
        );
        final modelsDir = p.join(tempDir.path, '.cow', 'models');

        Directory(p.join(modelsDir, 'a')).createSync(recursive: true);
        File(p.join(modelsDir, 'a', 'a.bin')).writeAsBytesSync([1]);

        expect(profilesPresent([profileA, profileB], modelsDir), isFalse);

        Directory(p.join(modelsDir, 'b')).createSync(recursive: true);
        File(p.join(modelsDir, 'b', 'b.bin')).writeAsBytesSync([2]);

        expect(profilesPresent([profileA, profileB], modelsDir), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    },
  );
}
