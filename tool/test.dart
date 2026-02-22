// To run:
// dart tool/test.dart              # all Dart packages with test/ dirs
// dart tool/test.dart cow_brain    # just cow_brain (Dart)
// dart tool/test.dart cow_mlx      # just cow_mlx (Swift, via test_mlx.dart)

import 'dart:io';

import 'src/helpers.dart';

Future<void> main(List<String> args) async {
  final target = args.firstOrNull;

  // cow_mlx is a Swift package — delegate to test_mlx.dart.
  if (target == 'cow_mlx' || target == 'packages/cow_mlx') {
    stdout.writeln('=== Testing packages/cow_mlx (Swift) ===');
    final code = await runCommand(
        'dart',
        [
          'tool/test_mlx.dart',
        ],
        workingDirectory: repoRoot().path);
    stdout.writeln('');
    exitCode = code;
    return;
  }

  final ok = await runOnPackages(testablePackages, target, (pkg) async {
    final testDir = Directory('${repoRoot().path}/$pkg/test');
    if (!testDir.existsSync()) return true;

    stdout.writeln('=== Testing $pkg ===');
    final code = await runCommand(
        'dart',
        [
          'test',
        ],
        workingDirectory: '${repoRoot().path}/$pkg');
    stdout.writeln('');
    return code == 0;
  });

  if (ok) stdout.writeln('All packages passed.');
  exitCode = ok ? 0 : 1;
}
