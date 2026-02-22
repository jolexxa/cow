// To run:
// dart tool/pub_get.dart             # all Dart packages
// dart tool/pub_get.dart cow_brain   # just cow_brain

import 'dart:io';

import 'src/helpers.dart';

Future<void> main(List<String> args) async {
  final target = args.firstOrNull;

  var ok = await runOnPackages(allDartPackages, target, (pkg) async {
    stdout.writeln('=== Getting packages for $pkg ===');
    final code = await runCommand('dart', [
      'pub',
      'get',
    ], workingDirectory: '${repoRoot().path}/$pkg');
    stdout.writeln('');
    return code == 0;
  });

  // Also resolve tool/ dependencies (args, path) so scripts like
  // download_llama_assets.dart can import external packages.
  if (ok && target == null) {
    stdout.writeln('=== Getting packages for tool ===');
    final toolCode = await runCommand('dart', [
      'pub',
      'get',
    ], workingDirectory: '${repoRoot().path}/tool');
    stdout.writeln('');
    if (toolCode != 0) ok = false;
  }

  if (ok) stdout.writeln('All packages resolved.');
  exitCode = ok ? 0 : 1;
}
