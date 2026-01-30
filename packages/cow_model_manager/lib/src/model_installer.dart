import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:cow_model_manager/src/cow_paths.dart';
import 'package:cow_model_manager/src/model_specs.dart';
import 'package:cow_model_manager/src/progress.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class ModelInstaller {
  ModelInstaller({
    CowPaths? paths,
    HttpClient? httpClient,
    http.Client? client,
    Clock? clock,
  }) : paths = paths ?? CowPaths(),
       _client = client ?? IOClient(httpClient ?? HttpClient()),
       _clock = clock ?? const Clock();

  final CowPaths paths;
  final http.Client _client;
  final Clock _clock;

  Stream<ModelInstallProgress> ensureInstalled(
    List<ModelProfileSpec> profiles, {
    ModelInstallController? controller,
  }) {
    final stream = StreamController<ModelInstallProgress>();
    unawaited(() async {
      final stopwatch = _clock.stopwatch()..start();
      var totalReceivedBytes = 0;
      var totalBytes = 0;
      var totalBytesKnown = true;
      var aborted = false;

      Future<void> emitProgress({
        required ModelProfileSpec profile,
        required ModelFileSpec file,
        required int fileReceivedBytes,
        required int? fileTotalBytes,
        required bool fileCompleted,
        required bool fileSkipped,
      }) async {
        if (stream.isClosed) {
          return;
        }
        stream.add(
          ModelInstallProgress(
            profile: profile,
            file: file,
            fileReceivedBytes: fileReceivedBytes,
            fileTotalBytes: fileTotalBytes,
            totalReceivedBytes: totalReceivedBytes,
            totalBytes: totalBytesKnown ? totalBytes : null,
            speedBytesPerSecond: _speedFor(stopwatch, totalReceivedBytes),
            fileCompleted: fileCompleted,
            fileSkipped: fileSkipped,
          ),
        );
      }

      Future<void> runFile({
        required ModelProfileSpec profile,
        required ModelFileSpec file,
      }) async {
        if (controller?.cancelled ?? false) {
          throw const ModelInstallCancelled();
        }
        if (aborted) {
          throw const ModelInstallCancelled();
        }
        final targetPath = paths.modelFilePath(profile, file);
        final targetFile = File(targetPath);
        if (targetFile.existsSync()) {
          final existingSize = targetFile.lengthSync();
          totalReceivedBytes += existingSize;
          totalBytes += existingSize;
          await emitProgress(
            profile: profile,
            file: file,
            fileReceivedBytes: existingSize,
            fileTotalBytes: existingSize,
            fileCompleted: true,
            fileSkipped: true,
          );
          return;
        }

        final tempPath = '$targetPath.part';
        final tempFile = File(tempPath);
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }

        final response = await _client.send(
          http.Request('GET', Uri.parse(file.url)),
        );
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'Failed to download ${file.url} (HTTP ${response.statusCode}).',
          );
        }

        final responseLength = response.contentLength;
        final fileTotalBytes = responseLength != null && responseLength >= 0
            ? responseLength
            : null;
        if (fileTotalBytes != null) {
          totalBytes += fileTotalBytes;
        } else {
          totalBytesKnown = false;
        }

        var fileReceivedBytes = 0;
        tempFile.createSync(recursive: true);
        final sink = tempFile.openWrite();
        var closed = false;
        try {
          await emitProgress(
            profile: profile,
            file: file,
            fileReceivedBytes: fileReceivedBytes,
            fileTotalBytes: fileTotalBytes,
            fileCompleted: false,
            fileSkipped: false,
          );
          await for (final chunk in response.stream) {
            if (controller?.cancelled ?? false) {
              throw const ModelInstallCancelled();
            }
            if (aborted) {
              throw const ModelInstallCancelled();
            }
            sink.add(chunk);
            fileReceivedBytes += chunk.length;
            totalReceivedBytes += chunk.length;
            await emitProgress(
              profile: profile,
              file: file,
              fileReceivedBytes: fileReceivedBytes,
              fileTotalBytes: fileTotalBytes,
              fileCompleted: false,
              fileSkipped: false,
            );
          }
        } on ModelInstallCancelled {
          await sink.close();
          closed = true;
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
          }
          rethrow;
        } catch (_) {
          await sink.close();
          closed = true;
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
          }
          rethrow;
        } finally {
          if (!closed) {
            await sink.close();
          }
        }

        await tempFile.rename(targetPath);

        await emitProgress(
          profile: profile,
          file: file,
          fileReceivedBytes: fileReceivedBytes,
          fileTotalBytes: fileTotalBytes,
          fileCompleted: true,
          fileSkipped: false,
        );
      }

      final tasks = <Future<void>>[];
      try {
        for (final profile in profiles) {
          final profileDir = Directory(paths.modelDir(profile));
          if (!profileDir.existsSync()) {
            profileDir.createSync(recursive: true);
          }
          for (final file in profile.files) {
            tasks.add(runFile(profile: profile, file: file));
          }
        }
        await Future.wait(tasks);
      } on ModelInstallCancelled {
        aborted = true;
        stream.addError(const ModelInstallCancelled());
      } on Exception catch (error, stackTrace) {
        aborted = true;
        stream.addError(error, stackTrace);
      } finally {
        await stream.close();
      }
    }());
    return stream.stream;
  }

  double? _speedFor(Stopwatch stopwatch, int totalReceivedBytes) {
    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed <= 0) {
      return null;
    }
    return totalReceivedBytes / (elapsed / 1000);
  }
}
