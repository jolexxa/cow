import 'dart:io';

import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:test/test.dart';

void main() {
  test('profileFilesPresent returns true only when all files exist', () async {
    final tempDir = await Directory.systemTemp.createTemp('cow-presence-');
    try {
      final profile = ModelProfileSpec(
        id: 'presence',
        supportsReasoning: false,
        files: const [
          ModelFileSpec(url: 'https://example.com/a', fileName: 'a.bin'),
          ModelFileSpec(url: 'https://example.com/b', fileName: 'b.bin'),
        ],
        entrypointFileName: 'a.bin',
      );
      final paths = CowPaths(homeDir: tempDir.path);

      Directory(paths.modelDir(profile)).createSync(recursive: true);
      File(
        paths.modelFilePath(profile, profile.files[0]),
      ).writeAsBytesSync([1, 2]);
      File(
        paths.modelFilePath(profile, profile.files[1]),
      ).writeAsBytesSync([3, 4]);

      expect(profileFilesPresent(profile, paths), isTrue);

      File(paths.modelFilePath(profile, profile.files[1])).deleteSync();
      expect(profileFilesPresent(profile, paths), isFalse);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'profilesPresent returns true only when all profiles are present',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('cow-profiles-');
      try {
        final profileA = ModelProfileSpec(
          id: 'a',
          supportsReasoning: false,
          files: const [
            ModelFileSpec(url: 'https://example.com/a', fileName: 'a.bin'),
          ],
          entrypointFileName: 'a.bin',
        );
        final profileB = ModelProfileSpec(
          id: 'b',
          supportsReasoning: true,
          files: const [
            ModelFileSpec(url: 'https://example.com/b', fileName: 'b.bin'),
          ],
          entrypointFileName: 'b.bin',
        );
        final paths = CowPaths(homeDir: tempDir.path);

        Directory(paths.modelDir(profileA)).createSync(recursive: true);
        File(
          paths.modelFilePath(profileA, profileA.files.single),
        ).writeAsBytesSync([1]);

        expect(profilesPresent([profileA, profileB], paths), isFalse);

        Directory(paths.modelDir(profileB)).createSync(recursive: true);
        File(
          paths.modelFilePath(profileB, profileB.files.single),
        ).writeAsBytesSync([2]);

        expect(profilesPresent([profileA, profileB], paths), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    },
  );
}
