// To run:
// dart tool/analyze.dart             # all Dart packages
// dart tool/analyze.dart cow_brain   # just cow_brain

import 'dart:io';

import 'src/helpers.dart';

Future<void> main(List<String> args) async {
  final target = args.firstOrNull;

  final ok = await runOnPackages(allDartPackages, target, (pkg) async {
    stdout.writeln('=== Analyzing $pkg ===');
    final code = await runCommand('dart', [
      'analyze',
      '--fatal-infos',
    ], workingDirectory: '${repoRoot().path}/$pkg');
    stdout.writeln('');
    return code == 0;
  });

  if (ok) stdout.writeln('All packages passed analysis.');
  exitCode = ok ? 0 : 1;
}
