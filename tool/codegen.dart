// To run:
// dart tool/codegen.dart             # all packages
// dart tool/codegen.dart cow_brain   # just cow_brain

import 'dart:io';

import 'src/helpers.dart';

Future<void> main(List<String> args) async {
  final target = args.firstOrNull;
  final root = repoRoot().path;

  if (target != null) {
    final resolved = resolvePackage(target);
    if (resolved == null) {
      stderr.writeln('Unknown package: $target');
      exitCode = 1;
      return;
    }

    var ran = false;

    if (buildRunnerPackages.contains(resolved)) {
      stdout.writeln('=== build_runner: $resolved ===');
      final code = await runCommand(
          'dart',
          [
            'run',
            'build_runner',
            'build',
            '--delete-conflicting-outputs',
          ],
          workingDirectory: '$root/$resolved');
      stdout.writeln('');
      if (code != 0) {
        exitCode = 1;
        return;
      }
      ran = true;
    }

    if (ffigenPackages.contains(resolved)) {
      stdout.writeln('=== ffigen: $resolved ===');
      final code = await runCommand(
          'dart',
          [
            'run',
            'ffigen',
            '--config',
            'tool/ffigen.yaml',
          ],
          workingDirectory: '$root/$resolved');
      stdout.writeln('');
      if (code != 0) {
        exitCode = 1;
        return;
      }
      ran = true;
    }

    if (!ran) {
      stderr.writeln('No codegen configured for $resolved');
      exitCode = 1;
    }
    return;
  }

  // Run all.
  for (final pkg in buildRunnerPackages) {
    stdout.writeln('=== build_runner: $pkg ===');
    final code = await runCommand(
        'dart',
        [
          'run',
          'build_runner',
          'build',
          '--delete-conflicting-outputs',
        ],
        workingDirectory: '$root/$pkg');
    stdout.writeln('');
    if (code != 0) {
      exitCode = 1;
      return;
    }
  }

  for (final pkg in ffigenPackages) {
    stdout.writeln('=== ffigen: $pkg ===');
    final code = await runCommand(
        'dart',
        [
          'run',
          'ffigen',
          '--config',
          'tool/ffigen.yaml',
        ],
        workingDirectory: '$root/$pkg');
    stdout.writeln('');
    if (code != 0) {
      exitCode = 1;
      return;
    }
  }

  stdout.writeln('Code generation complete.');
}
