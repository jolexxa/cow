// To run:
// dart tool/format.dart              # all Dart packages
// dart tool/format.dart cow_brain    # just cow_brain
// dart tool/format.dart --check      # check only (no writes)

import 'dart:io';

import 'src/helpers.dart';

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final target = args.where((a) => !a.startsWith('-')).firstOrNull;

  final ok = await runOnPackages(allDartPackages, target, (pkg) async {
    stdout.writeln('=== Formatting $pkg ===');
    final formatArgs = [
      'format',
      if (check) ...['--set-exit-if-changed', '--output=none'],
      '.',
    ];
    final code = await runCommand(
      'dart',
      formatArgs,
      workingDirectory: '${repoRoot().path}/$pkg',
    );
    stdout.writeln('');
    return code == 0;
  });

  if (ok) stdout.writeln('All packages formatted.');
  exitCode = ok ? 0 : 1;
}
