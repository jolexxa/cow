import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Clock _incrementingClock(DateTime start, Duration step) {
  var current = start;
  return Clock(() {
    final now = current;
    current = current.add(step);
    return now;
  });
}

Stream<List<int>> _streamWithDelays(
  List<List<int>> chunks, {
  List<Duration>? delays,
  void Function()? onFirstChunk,
  Object? error,
  Duration? errorDelay,
}) {
  final controller = StreamController<List<int>>();
  unawaited(() async {
    for (var i = 0; i < chunks.length; i++) {
      if (i == 0 && onFirstChunk != null) {
        onFirstChunk();
      }
      final delay = delays != null && i < delays.length ? delays[i] : null;
      if (delay != null && delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      controller.add(chunks[i]);
    }
    if (error != null) {
      if (errorDelay != null && errorDelay > Duration.zero) {
        await Future<void>.delayed(errorDelay);
      }
      controller.addError(error);
    }
    await controller.close();
  }());
  return controller.stream;
}

DownloadableModel _profileFor(
  Uri url, {
  String id = 'profile',
  String fileName = 'model.bin',
}) {
  return DownloadableModel(
    id: id,
    files: [DownloadableModelFile(url: url.toString(), fileName: fileName)],
    entrypointFileName: fileName,
  );
}

void main() {
  test('skips existing files and reports completion', () async {
    final tempDir = await Directory.systemTemp.createTemp('cow-skip-');
    try {
      final fileBytes = [1, 2, 3];
      final profile = _profileFor(Uri.parse('https://example.com/skip'));
      final modelsDir = p.join(tempDir.path, '.cow', 'models');
      Directory(p.join(modelsDir, profile.id)).createSync(recursive: true);
      File(
        p.join(modelsDir, profile.id, 'model.bin'),
      ).writeAsBytesSync(fileBytes);

      final installer = ModelInstaller(
        modelsDir: modelsDir,
        clock: Clock.fixed(DateTime(2024)),
      );
      final progress = await installer.ensureInstalled([profile]).toList();

      expect(progress, hasLength(1));
      final event = progress.single;
      expect(event.fileCompleted, isTrue);
      expect(event.fileSkipped, isTrue);
      expect(event.fileReceivedBytes, fileBytes.length);
      expect(event.fileTotalBytes, fileBytes.length);
      expect(event.totalReceivedBytes, fileBytes.length);
      expect(event.totalBytes, fileBytes.length);
      expect(event.speedBytesPerSecond, isNull);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('downloads missing files with progress and speed', () async {
    final tempDir = await Directory.systemTemp.createTemp('cow-download-');
    try {
      const payload = [5, 6, 7, 8];
      final client = MockClient.streaming((request, body) async {
        final stream = _streamWithDelays(
          [payload.sublist(0, 2), payload.sublist(2)],
          delays: const [Duration(milliseconds: 1), Duration(milliseconds: 1)],
        );
        return http.StreamedResponse(
          stream,
          HttpStatus.ok,
          contentLength: payload.length,
        );
      });

      final profile = _profileFor(Uri.parse('https://example.com/model.bin'));
      final modelsDir = p.join(tempDir.path, '.cow', 'models');
      Directory(p.join(modelsDir, profile.id)).createSync(recursive: true);
      final tempPath = p.join(modelsDir, profile.id, 'model.bin.part');
      File(tempPath).writeAsBytesSync([0, 0]);
      final installer = ModelInstaller(
        modelsDir: modelsDir,
        clock: _incrementingClock(
          DateTime(2024),
          const Duration(milliseconds: 5),
        ),
        client: client,
      );

      final progress = await installer.ensureInstalled([profile]).toList();

      expect(progress, isNotEmpty);
      expect(progress.last.fileCompleted, isTrue);
      expect(progress.last.fileSkipped, isFalse);
      expect(progress.last.fileReceivedBytes, payload.length);
      expect(progress.last.fileTotalBytes, payload.length);
      expect(progress.last.totalBytes, payload.length);
      expect(
        progress.any((event) => event.speedBytesPerSecond != null),
        isTrue,
      );

      final target = File(p.join(modelsDir, profile.id, 'model.bin'));
      expect(target.existsSync(), isTrue);
      expect(target.readAsBytesSync(), payload);
      expect(File('${target.path}.part').existsSync(), isFalse);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('handles unknown content length', () async {
    final tempDir = await Directory.systemTemp.createTemp('cow-unknown-');
    try {
      const payload = [9, 9, 9];
      final client = MockClient.streaming((request, body) async {
        final stream = _streamWithDelays([payload]);
        return http.StreamedResponse(stream, HttpStatus.ok);
      });

      final profile = _profileFor(
        Uri.parse('https://example.com/model.bin'),
        id: 'unknown',
      );
      final modelsDir = p.join(tempDir.path, '.cow', 'models');
      final installer = ModelInstaller(
        modelsDir: modelsDir,
        clock: _incrementingClock(
          DateTime(2024),
          const Duration(milliseconds: 2),
        ),
        client: client,
      );

      final progress = await installer.ensureInstalled([profile]).toList();

      expect(progress.last.fileCompleted, isTrue);
      expect(progress.last.fileTotalBytes, isNull);
      expect(progress.last.totalBytes, isNull);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('throws HttpException on non-200 response', () async {
    final tempDir = await Directory.systemTemp.createTemp('cow-error-');
    try {
      final client = MockClient.streaming((request, body) async {
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          HttpStatus.internalServerError,
        );
      });

      final profile = _profileFor(
        Uri.parse('https://example.com/bad.bin'),
        id: 'error',
      );
      final modelsDir = p.join(tempDir.path, '.cow', 'models');
      final installer = ModelInstaller(modelsDir: modelsDir, client: client);

      await expectLater(
        installer.ensureInstalled([profile]).drain<void>(),
        throwsA(isA<HttpException>()),
      );
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('cancels download and cleans temp file', () async {
    final tempDir = await Directory.systemTemp.createTemp('cow-cancel-');
    try {
      final controller = ModelInstallController()..cancel();
      final client = MockClient.streaming((request, body) async {
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          HttpStatus.ok,
          contentLength: 0,
        );
      });

      final profile = _profileFor(
        Uri.parse('https://example.com/slow.bin'),
        id: 'cancel',
      );
      final modelsDir = p.join(tempDir.path, '.cow', 'models');
      final installer = ModelInstaller(
        modelsDir: modelsDir,
        clock: Clock.fixed(DateTime(2024)),
        client: client,
      );

      await expectLater(
        installer.ensureInstalled([
          profile,
        ], controller: controller).drain<void>(),
        throwsA(isA<ModelInstallCancelled>()),
      );
      final targetPath = p.join(modelsDir, profile.id, 'model.bin');
      expect(File('$targetPath.part').existsSync(), isFalse);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('cancels mid-download and cleans temp file', () async {
    final tempDir = await Directory.systemTemp.createTemp('cow-cancel-mid-');
    try {
      final controller = ModelInstallController();
      final client = MockClient.streaming((request, body) async {
        final stream = _streamWithDelays(
          const [
            [1, 2, 3],
            [4, 5, 6],
          ],
          delays: const [Duration.zero, Duration(milliseconds: 30)],
          onFirstChunk: () {
            unawaited(
              Future<void>.delayed(
                const Duration(milliseconds: 5),
                controller.cancel,
              ),
            );
          },
        );
        return http.StreamedResponse(stream, HttpStatus.ok, contentLength: 6);
      });

      final profile = _profileFor(
        Uri.parse('https://example.com/slow.bin'),
        id: 'cancel-mid',
      );
      final modelsDir = p.join(tempDir.path, '.cow', 'models');
      final installer = ModelInstaller(
        modelsDir: modelsDir,
        clock: Clock.fixed(DateTime(2024)),
        client: client,
      );

      await expectLater(
        installer.ensureInstalled([
          profile,
        ], controller: controller).drain<void>(),
        throwsA(isA<ModelInstallCancelled>()),
      );

      final targetPath = p.join(modelsDir, profile.id, 'model.bin');
      expect(File('$targetPath.part').existsSync(), isFalse);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('cleans temp file when download stream errors', () async {
    final tempDir = await Directory.systemTemp.createTemp('cow-stream-error-');
    try {
      final client = MockClient.streaming((request, body) async {
        final stream = _streamWithDelays(const [
          [1, 2, 3],
        ], error: Exception('boom'));
        return http.StreamedResponse(stream, HttpStatus.ok, contentLength: 10);
      });

      final profile = _profileFor(
        Uri.parse('https://example.com/error.bin'),
        id: 'stream-error',
      );
      final modelsDir = p.join(tempDir.path, '.cow', 'models');
      final installer = ModelInstaller(
        modelsDir: modelsDir,
        clock: Clock.fixed(DateTime(2024)),
        client: client,
      );

      await expectLater(
        installer.ensureInstalled([profile]).drain<void>(),
        throwsA(isA<Exception>()),
      );

      final targetPath = p.join(modelsDir, profile.id, 'model.bin');
      expect(File('$targetPath.part').existsSync(), isFalse);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}
