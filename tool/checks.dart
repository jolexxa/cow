// Full CI-equivalent check. Run this before pushing.
//
// To run:
// dart tool/checks.dart

import 'dart:io';

import 'src/helpers.dart';

Future<void> main() async {
  final root = repoRoot().path;

  final steps = <(String, String, List<String>)>[
    ('Format', 'dart', ['tool/format.dart', '--check']),
    ('Analyze', 'dart', ['tool/analyze.dart']),
    ('Build CowMLX', 'dart', ['tool/build_mlx.dart']),
    ('Test CowMLX (Swift)', 'dart', ['tool/test_mlx.dart']),
    ('Test (Dart)', 'dart', ['tool/test.dart']),
    ('Coverage', 'dart', ['tool/coverage.dart']),
  ];

  for (var i = 0; i < steps.length; i++) {
    final (name, exe, args) = steps[i];
    stdout.writeln('========================================');
    stdout.writeln('  Step ${i + 1}/${steps.length}: $name');
    stdout.writeln('========================================');

    final code = await runCommand(exe, args, workingDirectory: root);
    if (code != 0) {
      exitCode = 1;
      return;
    }
  }

  stdout.writeln('');
  stdout.writeln('========================================');
  stdout.writeln('  All checks passed.');
  stdout.writeln('========================================');
}
