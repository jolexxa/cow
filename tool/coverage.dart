// To run:
// dart tool/coverage.dart             # all coverage-tracked packages
// dart tool/coverage.dart cow_brain   # just cow_brain

import 'dart:io';

import 'src/helpers.dart';

Future<void> main(List<String> args) async {
  final target = args.firstOrNull;

  final ok = await runOnPackages(coveragePackages, target, (pkg) async {
    final root = repoRoot().path;
    final pkgDir = '$root/$pkg';
    final name = pkg.split('/').last;

    if (!Directory('$pkgDir/test').existsSync()) {
      stdout.writeln('=== $name: no test/ directory, skipping ===');
      return true;
    }

    stdout.writeln('=== Coverage: $name ===');

    // Clean previous coverage.
    final coverageDir = Directory('$pkgDir/coverage');
    if (coverageDir.existsSync()) {
      coverageDir.deleteSync(recursive: true);
    }

    // Run tests with coverage.
    var code = await runCommand('dart', [
      'test',
      '--coverage=coverage',
    ], workingDirectory: pkgDir);
    if (code != 0) return false;

    // Format coverage to lcov.
    code = await runCommand('dart', [
      'pub',
      'global',
      'run',
      'coverage:format_coverage',
      '--lcov',
      '--in=coverage',
      '--out=coverage/lcov.info',
      '--report-on=lib',
      '--check-ignore',
      '--ignore-files=**/*.g.dart',
    ], workingDirectory: pkgDir);
    if (code != 0) return false;

    // Print summary if lcov is available.
    final lcovResult = await Process.run('which', ['lcov']);
    if (lcovResult.exitCode == 0) {
      await runCommand('lcov', [
        '--summary',
        'coverage/lcov.info',
      ], workingDirectory: pkgDir);
    } else {
      stdout.writeln('(install lcov for coverage summary)');
    }

    stdout.writeln('');
    return true;
  });

  if (ok) stdout.writeln('All coverage checks passed.');
  exitCode = ok ? 0 : 1;
}
