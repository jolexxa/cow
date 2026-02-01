// Not required for test files
import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaCpp', () {
    test('resolveLibraryPath prefers bundle lib directory', () {
      final tempDir = Directory.systemTemp.createTempSync('llama_cpp_test_');
      try {
        final binDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}bin',
        )..createSync(recursive: true);
        final libDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}lib',
        )..createSync(recursive: true);
        final libPath = File(
          '${libDir.path}${Platform.pathSeparator}'
          '${LlamaCpp.defaultLibraryFileName()}',
        )..writeAsBytesSync(const []);

        final resolved = LlamaCpp.resolveLibraryPath(executableDir: binDir);
        expect(resolved, equals(libPath.path));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('resolveLibraryPath falls back to executable dir', () {
      final resolved = LlamaCpp.resolveLibraryPath(
        executableDir: Directory('/opt/cow'),
      );
      expect(
        resolved,
        equals('/opt/cow/${LlamaCpp.defaultLibraryFileName()}'),
      );
    });
  });
}
